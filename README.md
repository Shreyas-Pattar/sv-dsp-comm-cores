# Synthesizable SystemVerilog DSP & Communications Cores

A collection of synthesizable, pipelined digital signal processing and communication IP cores implemented in SystemVerilog, verified bit-exact against Python golden references, and validated using SystemVerilog Assertions (SVA) in Xilinx Vivado ML Standard.

---

## 1. Pipelined 8-Point Radix-2 DIT FFT

A 3-stage pipelined Decimation-In-Time Fast Fourier Transform processor designed for baseband OFDM receivers.

### Architecture & Numerical Specs
- **Data Format:** Signed 16-bit Q1.15 fixed-point complex samples ($I/Q$).
- **Throughput & Latency:** 1 complete frame per clock cycle continuous throughput; deterministic 6 clock cycle latency (2 cycles per butterfly stage).
- **Quantization Protection:**
  - Round-half-up addition (`+ 1 << 14`) prior to truncation to eliminate negative DC bias drift.
  - Per-stage divide-by-2 arithmetic scaling (`>>> 1`) ensuring strictly bounded dynamic range across all 8 frequency bins without overflow.
- **Verification Methodology:** Bit-exact verification against Python/NumPy fixed-point reference models with zero LSB variance across DC, Kronecker delta, and tone frames.
- **Protocol SVA:** Embedded assertions verifying deterministic 6-cycle latency, reset invariants, and absence of unknown states (`'x`/`'z`) on valid output cycles.

### FPGA Synthesis Results (Target: Xilinx Zynq-7000 `xc7z010clg400-1`)
- **DSP48E1 Slices:** 60% (Mapped to complex multipliers)
- **Slice LUTs:** 11%
- **Slice Registers (FFs):** 3%

---

## 2. Hard-Decision Viterbi Decoder (K=3, Rate 1/2)

A forward error correction (FEC) decoder for convolutional codes compliant with industry generator polynomials $G_0 = 7_8$ (`111`), $G_1 = 5_8$ (`101`).

### Architecture & Specs
- **Trellis Configuration:** 4-state Add-Compare-Select (ACS) engine.
- **Metric Formulation:** Hamming distance Branch Metric Unit (BMU) with dynamic metric normalization to prevent 8-bit accumulator overflow.
- **Traceback Architecture:** 16-depth Register-Exchange network enabling low-latency, pointer-less bit reconstruction.
- **Verification:** Self-checking testbench with an on-the-fly convolutional encoder, channel bit-flip injection, and tail-flush sequence; verified 100% forward error correction of corrupted transmission bursts.

### FPGA Synthesis Results (Target: Xilinx Zynq-7000 `xc7z010clg400-1`)
- **DSP Slices:** 0% (Pure logic/register realization)
- **Slice LUTs:** 0.96%
- **Slice Registers (FFs):** 0.3%
- **I/O Utilization:** 7%

---

## Toolchain & Simulation Setup
- **Synthesis / Simulation:** Xilinx Vivado ML Standard Edition
- **Golden Models:** Python 3.10+ (NumPy)
- **Language Standard:** SystemVerilog (IEEE 1800-2012)
