`timescale 1ns / 1ps

module viterbi_decoder #(
    parameter int TB_DEPTH = 16
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        in_valid,
    input  logic [1:0]  rx_sym,    // {rx_c0, rx_c1}

    output logic        out_valid,
    output logic        decoded_bit
);

    // =========================================================================
    // 1. Branch Metric Unit (BMU)
    // Hamming distance between received symbol and all 4 possible codewords: 00, 01, 10, 11
    // =========================================================================
    logic [1:0] bm_00, bm_01, bm_10, bm_11;

    assign bm_00 = {1'b0, rx_sym[1] ^ 1'b0} + {1'b0, rx_sym[0] ^ 1'b0};
    assign bm_01 = {1'b0, rx_sym[1] ^ 1'b0} + {1'b0, rx_sym[0] ^ 1'b1};
    assign bm_10 = {1'b0, rx_sym[1] ^ 1'b1} + {1'b0, rx_sym[0] ^ 1'b0};
    assign bm_11 = {1'b0, rx_sym[1] ^ 1'b1} + {1'b0, rx_sym[0] ^ 1'b1};

    // =========================================================================
    // 2. Add-Compare-Select (ACS) Unit
    // State 0: Pred 0 (st 0, bm_00) vs Pred 1 (st 1, bm_11)
    // State 1: Pred 0 (st 2, bm_10) vs Pred 1 (st 3, bm_01)
    // State 2: Pred 0 (st 0, bm_11) vs Pred 1 (st 1, bm_00)
    // State 3: Pred 0 (st 2, bm_01) vs Pred 1 (st 3, bm_10)
    // =========================================================================
    localparam logic [7:0] MAX_METRIC = 8'd240;

    logic [7:0] pm [0:3];
    logic [7:0] next_pm [0:3];
    logic [3:0] decision; // Bit 0: decision for st 0, etc.

    // Path costs
    logic [7:0] c0_0, c0_1;
    logic [7:0] c1_0, c1_1;
    logic [7:0] c2_0, c2_1;
    logic [7:0] c3_0, c3_1;

    assign c0_0 = pm[0] + {6'd0, bm_00};
    assign c0_1 = pm[1] + {6'd0, bm_11};

    assign c1_0 = pm[2] + {6'd0, bm_10};
    assign c1_1 = pm[3] + {6'd0, bm_01};

    assign c2_0 = pm[0] + {6'd0, bm_11};
    assign c2_1 = pm[1] + {6'd0, bm_00};

    assign c3_0 = pm[2] + {6'd0, bm_01};
    assign c3_1 = pm[3] + {6'd0, bm_10};

    always_comb begin
        // ACS for State 0
        if (c0_0 <= c0_1) begin
            next_pm[0]  = c0_0;
            decision[0] = 1'b0; // survivor from state 0
        end else begin
            next_pm[0]  = c0_1;
            decision[0] = 1'b1; // survivor from state 1
        end

        // ACS for State 1
        if (c1_0 <= c1_1) begin
            next_pm[1]  = c1_0;
            decision[1] = 1'b0; // survivor from state 2
        end else begin
            next_pm[1]  = c1_1;
            decision[1] = 1'b1; // survivor from state 3
        end

        // ACS for State 2
        if (c2_0 <= c2_1) begin
            next_pm[2]  = c2_0;
            decision[2] = 1'b0; // survivor from state 0
        end else begin
            next_pm[2]  = c2_1;
            decision[2] = 1'b1; // survivor from state 1
        end

        // ACS for State 3
        if (c3_0 <= c3_1) begin
            next_pm[3]  = c3_0;
            decision[3] = 1'b0; // survivor from state 2
        end else begin
            next_pm[3]  = c3_1;
            decision[3] = 1'b1; // survivor from state 3
        end
    end

    // Path Metric State Registers with Normalization to prevent 8-bit overflow
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pm[0] <= 8'd0;
            pm[1] <= MAX_METRIC;
            pm[2] <= MAX_METRIC;
            pm[3] <= MAX_METRIC;
        end else if (in_valid) begin
            // If metrics grow large, subtract minimum to prevent wrap-around
            if (next_pm[0] > 8'd128 && next_pm[1] > 8'd128 &&
                next_pm[2] > 8'd128 && next_pm[3] > 8'd128) begin
                pm[0] <= next_pm[0] - 8'd128;
                pm[1] <= next_pm[1] - 8'd128;
                pm[2] <= next_pm[2] - 8'd128;
                pm[3] <= next_pm[3] - 8'd128;
            end else begin
                pm[0] <= next_pm[0];
                pm[1] <= next_pm[1];
                pm[2] <= next_pm[2];
                pm[3] <= next_pm[3];
            end
        end
    end

    // =========================================================================
    // 3. Survivor Path History (Register-Exchange Network)
    // =========================================================================
    logic [TB_DEPTH-1:0] sur_path [0:3];
    logic [TB_DEPTH-1:0] valid_pipe;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int k = 0; k < 4; k++) sur_path[k] <= '0;
            valid_pipe <= '0;
        end else if (in_valid) begin
            valid_pipe <= {valid_pipe[TB_DEPTH-2:0], 1'b1};

            // Register Exchange Update:
            // State 0 predecessors: (st 0, in=0) or (st 1, in=0)
            sur_path[0] <= decision[0] ? {sur_path[1][TB_DEPTH-2:0], 1'b0}
                                       : {sur_path[0][TB_DEPTH-2:0], 1'b0};

            // State 1 predecessors: (st 2, in=0) or (st 3, in=0)
            sur_path[1] <= decision[1] ? {sur_path[3][TB_DEPTH-2:0], 1'b0}
                                       : {sur_path[2][TB_DEPTH-2:0], 1'b0};

            // State 2 predecessors: (st 0, in=1) or (st 1, in=1)
            sur_path[2] <= decision[2] ? {sur_path[1][TB_DEPTH-2:0], 1'b1}
                                       : {sur_path[0][TB_DEPTH-2:0], 1'b1};

            // State 3 predecessors: (st 2, in=1) or (st 3, in=1)
            sur_path[3] <= decision[3] ? {sur_path[3][TB_DEPTH-2:0], 1'b1}
                                       : {sur_path[2][TB_DEPTH-2:0], 1'b1};
        end else begin
            valid_pipe <= {valid_pipe[TB_DEPTH-2:0], 1'b0};
        end
    end

    // =========================================================================
    // 4. Output Selection (Extract oldest bit from the best survivor path)
    // =========================================================================
    logic [1:0] best_state;

    always_comb begin
        if (pm[0] <= pm[1] && pm[0] <= pm[2] && pm[0] <= pm[3])
            best_state = 2'd0;
        else if (pm[1] <= pm[2] && pm[1] <= pm[3])
            best_state = 2'd1;
        else if (pm[2] <= pm[3])
            best_state = 2'd2;
        else
            best_state = 2'd3;
    end

    assign out_valid   = valid_pipe[TB_DEPTH-1];
    assign decoded_bit = sur_path[best_state][TB_DEPTH-1];

endmodule