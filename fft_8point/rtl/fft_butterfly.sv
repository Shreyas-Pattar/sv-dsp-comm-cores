`timescale 1ns / 1ps

module fft_butterfly #(
    parameter int WIDTH = 16
)(
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     in_valid,
    input  logic signed [WIDTH-1:0]  a_re_in,
    input  logic signed [WIDTH-1:0]  a_im_in,
    input  logic signed [WIDTH-1:0]  b_re_in,
    input  logic signed [WIDTH-1:0]  b_im_in,
    input  logic signed [WIDTH-1:0]  w_re_in,
    input  logic signed [WIDTH-1:0]  w_im_in,

    output logic                     out_valid,
    output logic signed [WIDTH-1:0]  x_re_out,
    output logic signed [WIDTH-1:0]  x_im_out,
    output logic signed [WIDTH-1:0]  y_re_out,
    output logic signed [WIDTH-1:0]  y_im_out
);

    // =========================================================================
    // PIPELINE STAGE 1: Real Multiplications into 32-bit DSP Registers
    // =========================================================================
    logic                     valid_pipe1;
    logic signed [WIDTH-1:0]  a_re_pipe1;
    logic signed [WIDTH-1:0]  a_im_pipe1;

    logic signed [31:0]       p_rr;
    logic signed [31:0]       p_ii;
    logic signed [31:0]       p_ri;
    logic signed [31:0]       p_ir;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe1 <= 1'b0;
            a_re_pipe1  <= '0;
            a_im_pipe1  <= '0;
            p_rr        <= '0;
            p_ii        <= '0;
            p_ri        <= '0;
            p_ir        <= '0;
        end else begin
            valid_pipe1 <= in_valid;
            a_re_pipe1  <= a_re_in;
            a_im_pipe1  <= a_im_in;

            p_rr        <= b_re_in * w_re_in;
            p_ii        <= b_im_in * w_im_in;
            p_ri        <= b_re_in * w_im_in;
            p_ir        <= b_im_in * w_re_in;
        end
    end

    // =========================================================================
    // PIPELINE STAGE 2 COMBINATIONAL: 33-bit Sub/Add, Rounding, Arithmetic Shift
    // =========================================================================
    logic signed [32:0] p_rr_ext, p_ii_ext, p_ri_ext, p_ir_ext;
    assign p_rr_ext = {{1{p_rr[31]}}, p_rr};
    assign p_ii_ext = {{1{p_ii[31]}}, p_ii};
    assign p_ri_ext = {{1{p_ri[31]}}, p_ri};
    assign p_ir_ext = {{1{p_ir[31]}}, p_ir};

    logic signed [32:0] t_re_raw;
    logic signed [32:0] t_im_raw;
    assign t_re_raw = p_rr_ext - p_ii_ext;
    assign t_im_raw = p_ri_ext + p_ir_ext;

    // Round constant: 1 << 14
    localparam logic signed [32:0] ROUND_VAL = 33'sh000004000;

    logic signed [32:0] t_re_rounded;
    logic signed [32:0] t_im_rounded;
    assign t_re_rounded = t_re_raw + ROUND_VAL;
    assign t_im_rounded = t_im_raw + ROUND_VAL;

    // Proper arithmetic shift preserving sign bit
    logic signed [32:0] t_re_shifted;
    logic signed [32:0] t_im_shifted;
    assign t_re_shifted = t_re_rounded >>> 15;
    assign t_im_shifted = t_im_rounded >>> 15;

    logic signed [15:0] t_re_q15;
    logic signed [15:0] t_im_q15;
    assign t_re_q15 = t_re_shifted[15:0];
    assign t_im_q15 = t_im_shifted[15:0];

    // Butterfly 17-bit sums/diffs
    logic signed [16:0] sum_re, sub_re;
    logic signed [16:0] sum_im, sub_im;

    assign sum_re = a_re_pipe1 + t_re_q15;
    assign sub_re = a_re_pipe1 - t_re_q15;
    assign sum_im = a_im_pipe1 + t_im_q15;
    assign sub_im = a_im_pipe1 - t_im_q15;

    // =========================================================================
    // PIPELINE STAGE 2 OUTPUT REGISTERS: Divide-by-2
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            x_re_out  <= '0;
            x_im_out  <= '0;
            y_re_out  <= '0;
            y_im_out  <= '0;
        end else begin
            out_valid <= valid_pipe1;
            x_re_out  <= sum_re >>> 1;
            x_im_out  <= sum_im >>> 1;
            y_re_out  <= sub_re >>> 1;
            y_im_out  <= sub_im >>> 1;
        end
    end

endmodule