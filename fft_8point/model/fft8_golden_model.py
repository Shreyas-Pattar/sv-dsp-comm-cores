"""
Golden Reference: 8-Point Parallel Pipelined FFT
Bit-exact against Vivado SystemVerilog RTL
"""

import numpy as np

def float_to_q15(x):
    return int(np.clip(np.round(x * 32768.0), -32768, 32767))

def butterfly(ar, ai, br, bi, wr, wi):
    # Verified Stage 1 + Stage 2 butterfly math
    p_rr = int(br) * int(wr)
    p_ii = int(bi) * int(wi)
    p_ri = int(br) * int(wi)
    p_ir = int(bi) * int(wr)

    t_r_raw = p_rr - p_ii
    t_i_raw = p_ri + p_ir

    t_r = (t_r_raw + (1 << 14)) >> 15
    t_i = (t_i_raw + (1 << 14)) >> 15

    t_r = int(np.clip(t_r, -32768, 32767))
    t_i = int(np.clip(t_i, -32768, 32767))

    xr = (int(ar) + t_r) >> 1
    xi = (int(ai) + t_i) >> 1
    yr = (int(ar) - t_r) >> 1
    yi = (int(ai) - t_i) >> 1
    return xr, xi, yr, yi

def fft8_fixed(x_in):
    """
    Bit-exact 8-point FFT pipeline matching the 3-stage RTL.
    x_in: list of 8 complex numbers (real, imag) in natural order [0..7]
    """
    # Twiddle factors
    W0 = (32767, 0)
    W1 = (23170, -23170)
    W2 = (0, -32768)
    W3 = (-23170, -23170)

    # Input bit-reversal swizzle: [0, 4, 2, 6, 1, 5, 3, 7]
    bit_rev_order = [0, 4, 2, 6, 1, 5, 3, 7]
    d = [x_in[i] for i in bit_rev_order]

    # --- STAGE 1 (Pairs: (0,1), (2,3), (4,5), (6,7) with W0) ---
    s1 = [None] * 8
    for i in range(4):
        a = d[2*i]
        b = d[2*i + 1]
        xr, xi, yr, yi = butterfly(a[0], a[1], b[0], b[1], W0[0], W0[1])
        s1[2*i]     = (xr, xi)
        s1[2*i + 1] = (yr, yi)

    # --- STAGE 2 (Strides of 2) ---
    s2 = [None] * 8
    # Group 0
    xr, xi, yr, yi = butterfly(s1[0][0], s1[0][1], s1[2][0], s1[2][1], W0[0], W0[1])
    s2[0] = (xr, xi); s2[2] = (yr, yi)
    xr, xi, yr, yi = butterfly(s1[1][0], s1[1][1], s1[3][0], s1[3][1], W2[0], W2[1])
    s2[1] = (xr, xi); s2[3] = (yr, yi)
    # Group 1
    xr, xi, yr, yi = butterfly(s1[4][0], s1[4][1], s1[6][0], s1[6][1], W0[0], W0[1])
    s2[4] = (xr, xi); s2[6] = (yr, yi)
    xr, xi, yr, yi = butterfly(s1[5][0], s1[5][1], s1[7][0], s1[7][1], W2[0], W2[1])
    s2[5] = (xr, xi); s2[7] = (yr, yi)

    # --- STAGE 3 (Strides of 4 with W0, W1, W2, W3) ---
    twiddles_s3 = [W0, W1, W2, W3]
    s3 = [None] * 8
    for i in range(4):
        w = twiddles_s3[i]
        xr, xi, yr, yi = butterfly(s2[i][0], s2[i][1], s2[i+4][0], s2[i+4][1], w[0], w[1])
        s3[i]   = (xr, xi)
        s3[i+4] = (yr, yi)

    return s3

# Quick validation against DC vector
dc_input = [(16384, 0)] * 8
dc_out = fft8_fixed(dc_input)
print("DC input output bin 0 (should carry total DC energy, rest 0):")
print(f"X[0]: {dc_out[0]} | X[1..7]: {dc_out[1:]}")