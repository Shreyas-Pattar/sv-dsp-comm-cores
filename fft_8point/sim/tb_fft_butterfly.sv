`timescale 1ns / 1ps

module tb_fft_butterfly;

    localparam int WIDTH = 16;
    localparam int CLK_PERIOD = 10; // 100 MHz clock

    logic                     clk;
    logic                     rst_n;
    logic                     in_valid;
    logic signed [WIDTH-1:0]  a_re_in, a_im_in;
    logic signed [WIDTH-1:0]  b_re_in, b_im_in;
    logic signed [WIDTH-1:0]  w_re_in, w_im_in;

    logic                     out_valid;
    logic signed [WIDTH-1:0]  x_re_out, x_im_out;
    logic signed [WIDTH-1:0]  y_re_out, y_im_out;

    // Instantiate UUT
    fft_butterfly #(.WIDTH(WIDTH)) uut (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (in_valid),
        .a_re_in   (a_re_in),
        .a_im_in   (a_im_in),
        .b_re_in   (b_re_in),
        .b_im_in   (b_im_in),
        .w_re_in   (w_re_in),
        .w_im_in   (w_im_in),
        .out_valid (out_valid),
        .x_re_out  (x_re_out),
        .x_im_out  (x_im_out),
        .y_re_out  (y_re_out),
        .y_im_out  (y_im_out)
    );

    // Clock Generation
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Golden vector structure
    typedef struct {
        shortint ar, ai;
        shortint br, bi;
        shortint wr, wi;
        shortint exp_xr, exp_xi;
        shortint exp_yr, exp_yi;
    } test_vec_t;

    test_vec_t test_vectors[16];
    test_vec_t expected_q[$];

    int match_count = 0;
    int mismatch_count = 0;

    // Monitor process
    always @(posedge clk) begin
        if (rst_n && out_valid) begin
            if (expected_q.size() > 0) begin
                test_vec_t gold = expected_q.pop_front();
                if ((x_re_out === gold.exp_xr) &&
                    (x_im_out === gold.exp_xi) &&
                    (y_re_out === gold.exp_yr) &&
                    (y_im_out === gold.exp_yi)) begin
                    match_count++;
                end else begin
                    mismatch_count++;
                    $display("[MISMATCH] Time=%0t ps | EXP: X=(%0d, %0d), Y=(%0d, %0d) | GOT: X=(%0d, %0d), Y=(%0d, %0d)",
                             $time, gold.exp_xr, gold.exp_xi, gold.exp_yr, gold.exp_yi,
                             x_re_out, x_im_out, y_re_out, y_im_out);
                end
            end else begin
                $display("[ERROR] Time=%0t ps | Unexpected out_valid asserted!", $time);
                mismatch_count++;
            end
        end
    end

    // Stimulus Driver
    initial begin
        // Mathematically validated golden vectors matching fixed-point RTL:
        // {ar, ai, br, bi, wr, wi, exp_xr, exp_xi, exp_yr, exp_yi}
        test_vectors[0]  = '{0, 0, 0, 0, 32767, 0, 0, 0, 0, 0};
        test_vectors[1]  = '{16384, 0, 16384, 0, 32767, 0, 16384, 0, 0, 0};
        test_vectors[2]  = '{16384, 0, -16384, 0, 32767, 0, 0, 0, 16383, 0};
        test_vectors[3]  = '{10000, 5000, -8000, 12000, 23170, -23170, 6414, 9571, 3586, -4571};
        test_vectors[4]  = '{32767, 32767, 32767, 32767, 32767, 0, 32766, 32766, 0, 0};
        test_vectors[5]  = '{-32768, -32768, 32767, 32767, -32768, 0, -32768, -32768, -1, -1};
        test_vectors[6]  = '{-9108, -7914, -24119, 793, 23170, -23170, -12801, 4850, 3693, -12765};
        test_vectors[7]  = '{-23412, -24103, -13009, 14920, 27244, -18204, -12970, -2236, -10443, -21868};
        test_vectors[8]  = '{1687, -1998, 23985, 23531, 30273, -12474, 16401, 5305, -14715, -7304};
        test_vectors[9]  = '{-23348, -13794, -13867, 8605, 32767, -260, -18573, -2540, -4775, -11255};
        test_vectors[10] = '{22208, 14210, 4851, -11939, 23170, -23170, 8598, 1169, 13610, 13041};
        test_vectors[11] = '{10860, 18512, 11624, 18361, 30273, 12474, 7304, 19950, 3555, -1438};
        test_vectors[12] = '{-7188, -22123, -20336, 12371, 32767, -391, -13688, -4755, 6500, -17368};
        test_vectors[13] = '{498, 14757, 1074, -7756, 32767, 0, 786, 3500, -288, 11256};
        test_vectors[14] = '{-7391, -7378, 16738, 21976, 27244, 18204, -2842, 10096, -4550, -17474};
        test_vectors[15] = '{22128, 7731, -21509, 21727, 23170, -23170, 11141, 19151, 10987, -11421};

        clk      = 0;
        rst_n    = 0;
        in_valid = 0;
        a_re_in  = '0;
        a_im_in  = '0;
        b_re_in  = '0;
        b_im_in  = '0;
        w_re_in  = '0;
        w_im_in  = '0;

        // Apply reset
        #(CLK_PERIOD * 3);
        rst_n = 1;
        #(CLK_PERIOD * 2);

        // Drive all 16 test vectors back-to-back
        for (int i = 0; i < 16; i++) begin
            @(posedge clk);
            in_valid <= 1'b1;
            a_re_in  <= test_vectors[i].ar;
            a_im_in  <= test_vectors[i].ai;
            b_re_in  <= test_vectors[i].br;
            b_im_in  <= test_vectors[i].bi;
            w_re_in  <= test_vectors[i].wr;
            w_im_in  <= test_vectors[i].wi;
            expected_q.push_back(test_vectors[i]);
        end

        // De-assert valid
        @(posedge clk);
        in_valid <= 1'b0;

        // Wait for pipeline drain (2 latency cycles + margin)
        #(CLK_PERIOD * 6);

        // Simulation report
        $display("\n========================================================");
        $display("          BUTTERFLY UNIT VERIFICATION REPORT");
        $display("========================================================");
        $display(" Total Vectors Tested : %0d", match_count + mismatch_count);
        $display(" Total Matches        : %0d", match_count);
        $display(" Total Mismatches     : %0d", mismatch_count);
        if (mismatch_count == 0 && match_count == 16) begin
            $display(" STATUS: TEST PASSED (BIT-EXACT MATCH)");
        end else begin
            $display(" STATUS: TEST FAILED");
        end
        $display("========================================================\n");

        $finish;
    end

endmodule