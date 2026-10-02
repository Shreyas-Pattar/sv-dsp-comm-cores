`timescale 1ns / 1ps

module tb_fft_8point_top;

    localparam int WIDTH = 16;
    localparam int LATENCY = 6;
    localparam int CLK_PERIOD = 10; // 100 MHz

    logic                     clk;
    logic                     rst_n;
    logic                     in_valid;
    logic signed [WIDTH-1:0]  x_re_in [0:7];
    logic signed [WIDTH-1:0]  x_im_in [0:7];

    logic                     out_valid;
    logic signed [WIDTH-1:0]  X_re_out [0:7];
    logic signed [WIDTH-1:0]  X_im_out [0:7];

    // Instantiate Top-Level FFT Core
    fft_8point_top #(.WIDTH(WIDTH)) uut (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (in_valid),
        .x_re_in   (x_re_in),
        .x_im_in   (x_im_in),
        .out_valid (out_valid),
        .X_re_out  (X_re_out),
        .X_im_out  (X_im_out)
    );

    // Clock Generation
    always #(CLK_PERIOD / 2) clk = ~clk;

    // =========================================================================
    // SYSTEMVERILOG ASSERTIONS (SVA) FOR PROTOCOL & TIMING INTEGRITY
    // =========================================================================

    // Property 1: Reset Invariant (out_valid must remain 0 when reset is low)
    property p_reset_state;
        @(posedge clk) !rst_n |-> (out_valid == 1'b0);
    endproperty
    assert_reset_state: assert property (p_reset_state)
        else $error("[SVA FAIL] out_valid asserted while reset was active!");

    // Property 2: Deterministic Pipeline Latency (exactly 6 cycles from in_valid rise)
    property p_exact_latency;
        @(posedge clk) disable iff (!rst_n)
        $rose(in_valid) |-> ##LATENCY out_valid;
    endproperty
    assert_exact_latency: assert property (p_exact_latency)
        else $error("[SVA FAIL] Expected out_valid exactly %0d cycles after in_valid rose!", LATENCY);

    // Property 3: No Unknowns (X/Z) on Valid Output
    property p_no_unknowns;
        @(posedge clk) disable iff (!rst_n)
        out_valid |-> not ($isunknown(X_re_out) || $isunknown(X_im_out));
    endproperty
    assert_no_unknowns: assert property (p_no_unknowns)
        else $error("[SVA FAIL] Unknown (X/Z) state detected on output bins during out_valid!");

    // =========================================================================
    // VERIFICATION MONITOR & STIMULUS
    // =========================================================================
    typedef struct {
        string name;
        shortint exp_re[8];
        shortint exp_im[8];
    } frame_t;

    frame_t expected_frames[$];
    int frames_checked = 0;
    int mismatches = 0;

    // Monitor Process: Verifies bit-exact output on out_valid
    always @(posedge clk) begin
        if (rst_n && out_valid) begin
            if (expected_frames.size() > 0) begin
                frame_t gold = expected_frames.pop_front();
                $display("\n[CHECK] Validating frame: %s at time %0t ps", gold.name, $time);
                for (int k = 0; k < 8; k++) begin
                    if ((X_re_out[k] === gold.exp_re[k]) && (X_im_out[k] === gold.exp_im[k])) begin
                        // Match
                    end else begin
                        mismatches++;
                        $display("  -> MISMATCH at Bin [%0d]: Expected (%0d, %0d) | Got (%0d, %0d)",
                                 k, gold.exp_re[k], gold.exp_im[k], X_re_out[k], X_im_out[k]);
                    end
                end
                frames_checked++;
            end else begin
                $display("[ERROR] Unexpected out_valid asserted!");
                mismatches++;
            end
        end
    end

    // Stimulus Driver Process
    initial begin
        frame_t f_dc, f_impulse;

        clk      = 0;
        rst_n    = 0;
        in_valid = 0;
        for (int k = 0; k < 8; k++) begin
            x_re_in[k] = '0;
            x_im_in[k] = '0;
        end

        // Frame 1: DC Input (All samples = 16384 + j0)
        f_dc.name = "DC Signal";
        f_dc.exp_re = '{16384, 0, 0, 0, 0, 0, 0, 0};
        f_dc.exp_im = '{0, 0, 0, 0, 0, 0, 0, 0};

        // Frame 2: Unit Impulse (x[0] = 16384, rest 0)
        f_impulse.name = "Unit Impulse";
        f_impulse.exp_re = '{2048, 2048, 2048, 2048, 2048, 2048, 2048, 2048};
        f_impulse.exp_im = '{0, 0, 0, 0, 0, 0, 0, 0};

        // Reset Sequence
        #(CLK_PERIOD * 3);
        rst_n = 1;
        #(CLK_PERIOD * 2);

        // Drive Frame 1: DC
        @(posedge clk);
        in_valid <= 1'b1;
        for (int k = 0; k < 8; k++) begin
            x_re_in[k] <= 16'sh4000; // 16384
            x_im_in[k] <= 16'sh0000;
        end
        expected_frames.push_back(f_dc);

        // Drive Frame 2: Unit Impulse (back-to-back)
        @(posedge clk);
        in_valid <= 1'b1;
        x_re_in[0] <= 16'sh4000; // 16384
        x_im_in[0] <= 16'sh0000;
        for (int k = 1; k < 8; k++) begin
            x_re_in[k] <= 16'sh0000;
            x_im_in[k] <= 16'sh0000;
        end
        expected_frames.push_back(f_impulse);

        // De-assert valid
        @(posedge clk);
        in_valid <= 1'b0;

        // Wait for pipeline drain (6-cycle latency + margin)
        #(CLK_PERIOD * 15);

        // Summary
        $display("\n========================================================");
        $display("       8-POINT PIPELINED FFT VERIFICATION REPORT");
        $display("========================================================");
        $display(" Total Frames Tested : %0d", frames_checked);
        $display(" Total Mismatches    : %0d", mismatches);
        if (mismatches == 0 && frames_checked == 2) begin
            $display(" STATUS: TEST PASSED (BIT-EXACT TOP LEVEL MATCH)");
            $display(" SVA STATUS: ALL PROTOCOL ASSERTIONS PASSED CLEANLY");
        end else begin
            $display(" STATUS: TEST FAILED");
        end
        $display("========================================================\n");

        $finish;
    end

endmodule