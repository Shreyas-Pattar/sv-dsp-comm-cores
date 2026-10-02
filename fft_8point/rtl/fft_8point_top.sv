`timescale 1ns / 1ps

module fft_8point_top #(
    parameter int WIDTH = 16
)(
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     in_valid,
    
    // 8 Complex Inputs (Natural Order 0..7)
    input  logic signed [WIDTH-1:0]  x_re_in [0:7],
    input  logic signed [WIDTH-1:0]  x_im_in [0:7],

    // Handshake and 8 Complex Outputs (Natural Frequency Order 0..7)
    output logic                     out_valid,
    output logic signed [WIDTH-1:0]  X_re_out [0:7],
    output logic signed [WIDTH-1:0]  X_im_out [0:7]
);

    // =========================================================================
    // Twiddle Factor Constants (Q1.15)
    // =========================================================================
    localparam logic signed [WIDTH-1:0] W0_R = 16'sh7FFF; // +32767 (~1.0)
    localparam logic signed [WIDTH-1:0] W0_I = 16'sh0000; // 0
    localparam logic signed [WIDTH-1:0] W1_R = 16'sh5A82; // +23170 (~sqrt(2)/2)
    localparam logic signed [WIDTH-1:0] W1_I = -16'sh5A82; // -23170
    localparam logic signed [WIDTH-1:0] W2_R = 16'sh0000; // 0
    localparam logic signed [WIDTH-1:0] W2_I = -16'sh8000; // -32768 (-1.0)
    localparam logic signed [WIDTH-1:0] W3_R = -16'sh5A82; // -23170
    localparam logic signed [WIDTH-1:0] W3_I = -16'sh5A82; // -23170

    // =========================================================================
    // Bit-Reversal Input Swizzle: [0, 4, 2, 6, 1, 5, 3, 7]
    // =========================================================================
    logic signed [WIDTH-1:0] in_swiz_re [0:7];
    logic signed [WIDTH-1:0] in_swiz_im [0:7];

    assign in_swiz_re[0] = x_re_in[0];
    assign in_swiz_re[1] = x_re_in[4];
    assign in_swiz_re[2] = x_re_in[2];
    assign in_swiz_re[3] = x_re_in[6];
    assign in_swiz_re[4] = x_re_in[1];
    assign in_swiz_re[5] = x_re_in[5];
    assign in_swiz_re[6] = x_re_in[3];
    assign in_swiz_re[7] = x_re_in[7];

    assign in_swiz_im[0] = x_im_in[0];
    assign in_swiz_im[1] = x_im_in[4];
    assign in_swiz_im[2] = x_im_in[2];
    assign in_swiz_im[3] = x_im_in[6];
    assign in_swiz_im[4] = x_im_in[1];
    assign in_swiz_im[5] = x_im_in[5];
    assign in_swiz_im[6] = x_im_in[3];
    assign in_swiz_im[7] = x_im_in[7];

    // =========================================================================
    // STAGE 1: 4 Butterflies, All using W0
    // =========================================================================
    logic        valid_s1;
    logic [3:0]  s1_valid_bus;
    logic signed [WIDTH-1:0] s1_re [0:7];
    logic signed [WIDTH-1:0] s1_im [0:7];

    assign valid_s1 = s1_valid_bus[0];

    genvar i;
    generate
        for (i = 0; i < 4; i++) begin : gen_stage1
            fft_butterfly #(.WIDTH(WIDTH)) u_bf1 (
                .clk       (clk),
                .rst_n     (rst_n),
                .in_valid  (in_valid),
                .a_re_in   (in_swiz_re[2*i]),
                .a_im_in   (in_swiz_im[2*i]),
                .b_re_in   (in_swiz_re[2*i + 1]),
                .b_im_in   (in_swiz_im[2*i + 1]),
                .w_re_in   (W0_R),
                .w_im_in   (W0_I),
                .out_valid (s1_valid_bus[i]),
                .x_re_out  (s1_re[2*i]),
                .x_im_out  (s1_im[2*i]),
                .y_re_out  (s1_re[2*i + 1]),
                .y_im_out  (s1_im[2*i + 1])
            );
        end
    endgenerate

    // =========================================================================
    // STAGE 2: 4 Butterflies (Stride 2)
    // =========================================================================
    logic        valid_s2;
    logic signed [WIDTH-1:0] s2_re [0:7];
    logic signed [WIDTH-1:0] s2_im [0:7];

    // Butterfly 0 (Group 0 top, W0)
    fft_butterfly #(.WIDTH(WIDTH)) u_bf2_0 (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (valid_s1),
        .a_re_in   (s1_re[0]),
        .a_im_in   (s1_im[0]),
        .b_re_in   (s1_re[2]),
        .b_im_in   (s1_im[2]),
        .w_re_in   (W0_R),
        .w_im_in   (W0_I),
        .out_valid (valid_s2),
        .x_re_out  (s2_re[0]),
        .x_im_out  (s2_im[0]),
        .y_re_out  (s2_re[2]),
        .y_im_out  (s2_im[2])
    );

    // Butterfly 1 (Group 0 bottom, W2)
    fft_butterfly #(.WIDTH(WIDTH)) u_bf2_1 (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (valid_s1),
        .a_re_in   (s1_re[1]),
        .a_im_in   (s1_im[1]),
        .b_re_in   (s1_re[3]),
        .b_im_in   (s1_im[3]),
        .w_re_in   (W2_R),
        .w_im_in   (W2_I),
        .out_valid (),
        .x_re_out  (s2_re[1]),
        .x_im_out  (s2_im[1]),
        .y_re_out  (s2_re[3]),
        .y_im_out  (s2_im[3])
    );

    // Butterfly 2 (Group 1 top, W0)
    fft_butterfly #(.WIDTH(WIDTH)) u_bf2_2 (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (valid_s1),
        .a_re_in   (s1_re[4]),
        .a_im_in   (s1_im[4]),
        .b_re_in   (s1_re[6]),
        .b_im_in   (s1_im[6]),
        .w_re_in   (W0_R),
        .w_im_in   (W0_I),
        .out_valid (),
        .x_re_out  (s2_re[4]),
        .x_im_out  (s2_im[4]),
        .y_re_out  (s2_re[6]),
        .y_im_out  (s2_im[6])
    );

    // Butterfly 3 (Group 1 bottom, W2)
    fft_butterfly #(.WIDTH(WIDTH)) u_bf2_3 (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (valid_s1),
        .a_re_in   (s1_re[5]),
        .a_im_in   (s1_im[5]),
        .b_re_in   (s1_re[7]),
        .b_im_in   (s1_im[7]),
        .w_re_in   (W2_R),
        .w_im_in   (W2_I),
        .out_valid (),
        .x_re_out  (s2_re[5]),
        .x_im_out  (s2_im[5]),
        .y_re_out  (s2_re[7]),
        .y_im_out  (s2_im[7])
    );

    // =========================================================================
    // STAGE 3: 4 Butterflies (Stride 4) with W0, W1, W2, W3
    // =========================================================================
    logic signed [WIDTH-1:0] tw_re_s3 [0:3];
    logic signed [WIDTH-1:0] tw_im_s3 [0:3];
    logic [3:0]  s3_valid_bus;

    assign tw_re_s3[0] = W0_R; assign tw_im_s3[0] = W0_I;
    assign tw_re_s3[1] = W1_R; assign tw_im_s3[1] = W1_I;
    assign tw_re_s3[2] = W2_R; assign tw_im_s3[2] = W2_I;
    assign tw_re_s3[3] = W3_R; assign tw_im_s3[3] = W3_I;

    assign out_valid = s3_valid_bus[0];

    generate
        for (i = 0; i < 4; i++) begin : gen_stage3
            fft_butterfly #(.WIDTH(WIDTH)) u_bf3 (
                .clk       (clk),
                .rst_n     (rst_n),
                .in_valid  (valid_s2),
                .a_re_in   (s2_re[i]),
                .a_im_in   (s2_im[i]),
                .b_re_in   (s2_re[i + 4]),
                .b_im_in   (s2_im[i + 4]),
                .w_re_in   (tw_re_s3[i]),
                .w_im_in   (tw_im_s3[i]),
                .out_valid (s3_valid_bus[i]),
                .x_re_out  (X_re_out[i]),
                .x_im_out  (X_im_out[i]),
                .y_re_out  (X_re_out[i + 4]),
                .y_im_out  (X_im_out[i + 4])
            );
        end
    endgenerate

endmodule