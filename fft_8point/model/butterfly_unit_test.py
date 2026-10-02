"""
Golden Model: Radix-2 Butterfly Unit
Q1.15 Signed Fixed-Point Arithmetic (-32768 to +32767)
"""

import numpy as np

def float_to_q15(x):
    """Convert float in [-1.0, 1.0) to signed 16-bit integer."""
    val = int(np.round(x * 32768.0))
    return int(np.clip(val, -32768, 32767))

def butterfly_golden(ar, ai, br, bi, wr, wi):
    """
    Bit-accurate Radix-2 Butterfly:
      T = B * W
      X = (A + T) / 2
      Y = (A - T) / 2
    """
    # 1. Complex multiplication: B * W
    p_rr = int(br) * int(wr)
    p_ii = int(bi) * int(wi)
    p_ri = int(br) * int(wi)
    p_ir = int(bi) * int(wr)

    # 33-bit intermediate results (Q3.30)
    t_r_raw = p_rr - p_ii
    t_i_raw = p_ri + p_ir

    # Round-half-up: add 1 << 14 before arithmetic right-shift by 15
    t_r = (t_r_raw + (1 << 14)) >> 15
    t_i = (t_i_raw + (1 << 14)) >> 15

    # Clamp to signed 16-bit range
    t_r = int(np.clip(t_r, -32768, 32767))
    t_i = int(np.clip(t_i, -32768, 32767))

    # 2. Butterfly add/sub with divide-by-2 scaling (arithmetic shift right by 1)
    xr = (int(ar) + t_r) >> 1
    xi = (int(ai) + t_i) >> 1
    yr = (int(ar) - t_r) >> 1
    yi = (int(ai) - t_i) >> 1

    return int(xr), int(xi), int(yr), int(yi)

# Deterministic vectors: corner cases + random numbers
np.random.seed(42)
test_suite = [
    # (Ar, Ai, Br, Bi, Wr, Wi)
    (0, 0, 0, 0, 32767, 0),                       # All zeros
    (16384, 0, 16384, 0, 32767, 0),               # DC input, W = 1.0
    (16384, 0, -16384, 0, 32767, 0),              # Inverted input
    (10000, 5000, -8000, 12000, 23170, -23170),   # W = e^(-j*pi/4)
    (32767, 32767, 32767, 32767, 32767, 0),       # Maximum positive
    (-32768, -32768, 32767, 32767, -32768, 0),    # Mixed extremes
]

for _ in range(10):
    ar = int(np.random.randint(-25000, 25000))
    ai = int(np.random.randint(-25000, 25000))
    br = int(np.random.randint(-25000, 25000))
    bi = int(np.random.randint(-25000, 25000))
    theta = np.random.uniform(0, 2 * np.pi)
    wr = float_to_q15(np.cos(theta))
    wi = float_to_q15(-np.sin(theta))
    test_suite.append((ar, ai, br, bi, wr, wi))

print(f"Generated {len(test_suite)} vectors successfully.")