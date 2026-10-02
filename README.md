# Synthesizable SystemVerilog DSP & Communications Cores

A collection of synthesizable, pipelined digital signal processing and communication
IP cores implemented in SystemVerilog, verified bit-exact against Python golden
reference models, and validated using SystemVerilog Assertions (SVA) in Xilinx
Vivado ML Standard.

---

## 1. Pipelined 8-Point Radix-2 DIT FFT

A 3-stage pipelined Decimation-In-Time Fast Fourier Transform processor, designed as
a baseband building block for OFDM receivers (the same FFT operation used in 5G NR /
LTE / Wi-Fi OFDM demodulation).

### Block diagram

```
Input (8 complex samples, Q1.15)
        |
        v
+----------------+     +----------------+     +----------------+
|   Stage 0      | --> |   Stage 1      | --> |   Stage 2      | --> Output
| 4 butterflies  |     | 4 butterflies  |     | 4 butterflies  |     (bit-reversed
| twiddle W0     |     | twiddle W1     |     | twiddle W2     |      order)
+----------------+     +----------------+     +----------------+
   2 cyc latency           2 cyc latency           2 cyc latency
        \______________________6 cycle total latency_____________/
```

Each stage: complex butterfly (add/subtract) + complex multiply by a twiddle factor,
followed by a pipeline register.

### Architecture & numerical specs

- **Data format:** signed 16-bit Q1.15 fixed-point complex samples (I/Q).
- **Throughput & latency:** 1 complete 8-sample frame accepted per clock cycle
  (fully pipelined, continuous throughput); deterministic 6-cycle latency from input
  to output (2 cycles per butterfly stage, 3 stages).
- **Quantization handling:**
  - Round-half-up before truncation (`+ (1 << 14)` prior to shifting down) to
    eliminate the negative DC bias that plain truncation introduces.
  - Per-stage divide-by-2 scaling (`>>> 1`) after each butterfly stage, keeping the
    dynamic range strictly bounded across all 8 frequency bins with no overflow.
- **Verification methodology:** bit-exact comparison against a Python/NumPy
  fixed-point golden model, confirmed with zero LSB (least-significant-bit)
  variance across DC, Kronecker-delta (unit impulse), and single-tone test frames.
- **SVA protocol checks:** deterministic 6-cycle latency is enforced, reset
  invariants hold, and no unknown (`'x`/`'z`) values appear on the output bus during
  any cycle where the output-valid signal is asserted.

### FPGA synthesis results (target: Xilinx Zynq-7000 `xc7z010clg400-1`)

| Resource | Utilization |
|---|---|
| DSP48E1 slices | 60% (mapped to the complex multipliers) |
| Slice LUTs | 11% |
| Slice registers (FFs) | 3% |

---

## 2. Hard-Decision Viterbi Decoder (K=3, Rate 1/2)

A forward error correction (FEC) decoder for convolutional codes, using generator
polynomials G0 = 7₈ (`111`) and G1 = 5₈ (`101`) — a standard constraint-length-3,
rate-1/2 convolutional code widely used as a reference/teaching code and historically
in systems such as early GPS and legacy digital radio links.

### Architecture & specs

- **Trellis configuration:** 4-state Add-Compare-Select (ACS) engine.
- **Metric formulation:** Hamming-distance branch metric unit (BMU), with dynamic
  metric normalization to prevent 8-bit accumulator overflow over long sequences.
- **Traceback architecture:** 16-depth register-exchange network, giving low-latency,
  pointer-less bit reconstruction (no memory-pointer traceback, unlike the classic
  trace-back-through-RAM approach — trades some area for simpler, faster logic).
- **Verification:** self-checking testbench that includes its own on-the-fly
  convolutional encoder, deliberate channel bit-flip injection, and a tail-flush
  sequence; confirmed 100% correction of all injected single/burst errors within the
  code's correction capability across the test run.

### FPGA synthesis results (target: Xilinx Zynq-7000 `xc7z010clg400-1`)

| Resource | Utilization |
|---|---|
| DSP slices | 0% (pure logic/register realization — no multipliers needed for Hamming-distance ACS) |
| Slice LUTs | 0.96% |
| Slice registers (FFs) | 0.3% |
| I/O utilization | 7% |

---

## Toolchain & simulation setup

- **Synthesis / simulation:** Xilinx Vivado ML Standard Edition
- **Golden models:** Python 3.10+ (NumPy)
- **Language standard:** SystemVerilog (IEEE 1800-2012)

## Repository structure

```
sv-dsp-comm-cores/
├── fft_8point/
│   ├── model/        golden_fft.py — Python/NumPy fixed-point reference
│   ├── rtl/           fft_8point.sv — synthesizable pipelined FFT
│   └── sim/           tb_fft_8point.sv — self-checking testbench + SVA
├── viterbi_decoder/
│   ├── model/        golden_viterbi.py — reference encoder/decoder
│   ├── rtl/           viterbi_decoder.sv — synthesizable ACS decoder
│   └── sim/           tb_viterbi_decoder.sv — self-checking testbench
├── LICENSE
├── requirements.txt
└── README.md
```

## How to run

1. Install Xilinx Vivado ML Standard (free WebPACK edition is sufficient for this
   target device).
2. Open each `sim/` testbench in the Vivado simulator (XSIM) and run — both
   testbenches are self-checking and report PASS/FAIL directly in the simulation log.
3. Golden models (`model/*.py`) can be re-run independently with
   `pip install -r requirements.txt` followed by `python3 model/golden_fft.py` (or
   `golden_viterbi.py`) to regenerate the reference vectors the testbenches compare
   against.

## Scope and limitations

- The FFT core is fixed at 8 points; a larger (e.g. 64-point) transform would need
  either a deeper pipeline or a different (e.g. mixed-radix) architecture.
- The Viterbi decoder uses hard-decision (bit-level) inputs, not soft-decision
  (LLR-based) inputs — soft-decision Viterbi gives better coding gain and is more
  common in real wireless standards, but is a meaningfully larger design.
- Both cores were verified via targeted test vectors (DC, impulse, single-tone,
  and injected bit-flip bursts) rather than exhaustive or randomized/
  constrained-random stimulus — broader coverage (e.g. SystemVerilog functional
  coverage, randomized frame generation) is a natural next step.
- Synthesis results are from Vivado's implementation reports for the stated target
  part only; timing closure (maximum clock frequency) is not yet characterized here.
