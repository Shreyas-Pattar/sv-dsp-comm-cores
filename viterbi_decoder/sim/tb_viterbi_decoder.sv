`timescale 1ns / 1ps

module tb_viterbi_decoder;

    localparam int CLK_PERIOD = 10;
    localparam int TB_DEPTH   = 16;
    localparam int NUM_BITS   = 32;

    logic        clk;
    logic        rst_n;
    logic        in_valid;
    logic [1:0]  rx_sym;
    logic        out_valid;
    logic        decoded_bit;

    // Instantiate Decoder UUT
    viterbi_decoder #(
        .TB_DEPTH(TB_DEPTH)
    ) uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .in_valid    (in_valid),
        .rx_sym      (rx_sym),
        .out_valid   (out_valid),
        .decoded_bit (decoded_bit)
    );

    // Clock Generation
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Convolutional Encoder Task (G0=7, G1=5)
    // s1 is MSB, s0 is LSB of state register
    function automatic logic [1:0] encode_bit(input logic u, inout logic [1:0] state);
        logic c0, c1;
        c0 = u ^ state[1] ^ state[0];
        c1 = u ^ state[0];
        state = {u, state[1]};
        return {c0, c1};
    endfunction

    logic [NUM_BITS-1:0] tx_data = 32'hA5C3_964B;
    logic golden_queue[$];
    int decoded_count = 0;
    int error_count = 0;

    // Monitor Process
    always @(posedge clk) begin
        if (rst_n && out_valid) begin
            if (golden_queue.size() > 0) begin
                logic exp = golden_queue.pop_front();
                if (decoded_bit === exp) begin
                    $display("Time=%0t ps | Decoded bit [%0d]: %0b (Expected: %0b) [MATCH]",
                             $time, decoded_count, decoded_bit, exp);
                end else begin
                    error_count++;
                    $display("Time=%0t ps | Decoded bit [%0d]: %0b (Expected: %0b) [MISMATCH!]",
                             $time, decoded_count, decoded_bit, exp);
                end
                decoded_count++;
            end
        end
    end

    // Stimulus Process
    initial begin
        logic [1:0] enc_state;
        logic [1:0] sym;
        logic curr_bit;

        clk       = 0;
        rst_n     = 0;
        in_valid  = 0;
        rx_sym    = '0;
        enc_state = 2'b00;

        // Reset
        #(CLK_PERIOD * 3);
        rst_n = 1;
        #(CLK_PERIOD * 2);

        // 1. Transmit 32 Data Bits with 3 Deliberate Channel Bit Errors
        for (int i = 0; i < NUM_BITS; i++) begin
            curr_bit = tx_data[NUM_BITS - 1 - i];
            sym = encode_bit(curr_bit, enc_state);

            // Inject channel errors at symbols 5, 14, and 23
            if (i == 5)  sym[0] = ~sym[0]; // Channel bit error 1
            if (i == 14) sym[1] = ~sym[1]; // Channel bit error 2
            if (i == 23) sym[0] = ~sym[0]; // Channel bit error 3

            @(posedge clk);
            in_valid <= 1'b1;
            rx_sym   <= sym;
            golden_queue.push_back(curr_bit);
        end

        // 2. Transmit TB_DEPTH Zero Flush Bits Through Encoder
        // This ensures the convolutional code gracefully flushes through valid trellis states
        for (int i = 0; i < TB_DEPTH; i++) begin
            sym = encode_bit(1'b0, enc_state);
            @(posedge clk);
            in_valid <= 1'b1;
            rx_sym   <= sym;
        end

        // 3. De-assert valid
        @(posedge clk);
        in_valid <= 1'b0;

        #(CLK_PERIOD * 5);

        // Final Report
        $display("\n========================================================");
        $display("         VITERBI DECODER HARDWARE VERIFICATION");
        $display("========================================================");
        $display(" Total Information Bits : %0d", decoded_count);
        $display(" Injected Channel Errors: 3 bit flips");
        $display(" Uncorrected Errors     : %0d", error_count);
        if (error_count == 0 && decoded_count == NUM_BITS) begin
            $display(" STATUS: TEST PASSED (100%% NOISE CORRECTION ACHIEVED)");
        end else begin
            $display(" STATUS: TEST FAILED");
        end
        $display("========================================================\n");

        $finish;
    end

endmodule