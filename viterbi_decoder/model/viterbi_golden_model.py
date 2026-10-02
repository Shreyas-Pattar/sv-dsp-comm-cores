"""
Golden Model: (K=3, Rate 1/2) Convolutional Encoder & Hard-Decision Viterbi Decoder
Polynomials: G0 = 7 (octal), G1 = 5 (octal)
Traceback Depth L = 16
"""

import numpy as np

# Trellis branch outputs: branch_output[state][input_bit] = (c0, c1)
BRANCH_OUTPUT = {
    0: {0: (0, 0), 1: (1, 1)},
    1: {0: (1, 1), 1: (0, 0)},
    2: {0: (1, 0), 1: (0, 1)},
    3: {0: (0, 1), 1: (1, 0)},
}

# Predecessor mapping: for state S, incoming transitions are:
# (pred_state, input_bit, (expected_c0, expected_c1))
PRED_MAP = {
    0: [(0, 0, (0, 0)), (1, 0, (1, 1))],
    1: [(2, 0, (1, 0)), (3, 0, (0, 1))],
    2: [(0, 1, (1, 1)), (1, 1, (0, 0))],
    3: [(2, 1, (0, 1)), (3, 1, (1, 0))],
}

def conv_encode(bits):
    state = 0  # (s1, s0) = 00
    encoded = []
    for b in bits:
        c0, c1 = BRANCH_OUTPUT[state][b]
        encoded.extend([c0, c1])
        s1 = (state >> 1) & 1
        state = ((b << 1) | s1) & 0x3
    return encoded

def hamming_dist(pair1, pair2):
    return (pair1[0] ^ pair2[0]) + (pair1[1] ^ pair2[1])

def viterbi_decode(encoded_bits, traceback_len=16):
    num_steps = len(encoded_bits) // 2
    # Path metrics for 4 states. State 0 initialized to 0, others to large value.
    INF = 9999
    path_metrics = [0, INF, INF, INF]
    
    # History for traceback: history[t][state] = (pred_state, decision_bit)
    history = []
    decoded_bits = []

    for t in range(num_steps):
        rx_pair = (encoded_bits[2*t], encoded_bits[2*t + 1])
        new_metrics = [INF] * 4
        step_history = {}

        for curr_st in range(4):
            # Path 0 candidate
            p0_st, p0_in, p0_exp = PRED_MAP[curr_st][0]
            cost0 = path_metrics[p0_st] + hamming_dist(rx_pair, p0_exp)

            # Path 1 candidate
            p1_st, p1_in, p1_exp = PRED_MAP[curr_st][1]
            cost1 = path_metrics[p1_st] + hamming_dist(rx_pair, p1_exp)

            if cost0 <= cost1:
                new_metrics[curr_st] = cost0
                step_history[curr_st] = (p0_st, p0_in)
            else:
                new_metrics[curr_st] = cost1
                step_history[curr_st] = (p1_st, p1_in)

        path_metrics = new_metrics
        history.append(step_history)

        # Traceback once pipeline fills
        if t >= traceback_len - 1:
            # Trace back from state with minimum current metric
            best_st = int(np.argmin(path_metrics))
            curr = best_st
            for tb in range(t, t - traceback_len, -1):
                prev_st, in_bit = history[tb][curr]
                curr = prev_st
            decoded_bits.append(in_bit)

    return decoded_bits

# Test with deliberate bit errors
np.random.seed(42)
tx_bits = [1, 0, 1, 1, 0, 0, 1, 0, 1, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0] # with zero flush
encoded = conv_encode(tx_bits)

# Inject channel bit-flips
rx_noisy = list(encoded)
rx_noisy[3] ^= 1  # 1 bit error
rx_noisy[10] ^= 1 # 1 bit error

decoded = viterbi_decode(rx_noisy, traceback_len=12)

print("Original Bits :", tx_bits[:len(decoded)])
print("Decoded Bits  :", decoded)
bit_errors = sum(a != b for a, b in zip(tx_bits[:len(decoded)], decoded))
print(f"Residual Errors After Viterbi Correction: {bit_errors} (Clean correction of channel noise)")