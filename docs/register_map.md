# Register Map

Logical register and memory contents

## Overview

The design contains three writable memories plus a set of scalar control, status, and calibration registers:

- **Play configuration memory**: 16 entries
- **Measure configuration memory**: 4 entries
- **Instruction memory**: 32 entries
- **Scalar registers**: control, status, calibration, and measurement-result state

Sizing is defined in `rtl_pkg.sv`:

- `PlayCfgDepth = 16`
- `MeasCfgDepth = 4`
- `InstrDepth = 32`

## Scalar Registers

These are the logical scalar registers exposed by `register_bank`.

| Register | Width | Type | Description | Reset value |
|---|---:|---|---|---:|
| `start_exp` | 1 | control pulse/sticky until cleared | Starts experiment sequencing | `0` |
| `soft_reset_req` | 1 | control pulse/sticky | Requests soft reset | `0` |
| `read_all_pulse` | 1 | pulse | Requests full register dump/readback | `0` |
| `reset_wait_cycles` | 32 | unsigned | Wait interval used by `WAIT_RESET` | `0` after reset, default ROM preloads `1000` |
| `play_cfg_any_valid` | 1 | status | High when any play config entry is valid | `0` |
| `measure_cfg_any_valid` | 1 | status | High when any measure config entry is valid | `0` |
| `instr_any_valid` | 1 | status | High when any instruction entry is valid | `0` |
| `seq_busy` | 1 | status | Mirrors sequencer busy input | external |
| `seq_done_sticky` | 1 | sticky status | Set when sequence completes, cleared on new start/reset | `0` |
| `cal_sample_count` | 16 | unsigned | Number of samples accumulated in calibration averaging | `0` |
| `cal_i_avg` | 16 | signed | Latest averaged I result from calibration accumulator path | `0` |
| `cal_q_avg` | 16 | signed | Latest averaged Q result from calibration accumulator path | `0` |
| `cal_i0_ref` | 16 | signed | Stored I reference for prepared \|0> | `0` |
| `cal_q0_ref` | 16 | signed | Stored Q reference for prepared \|0> | `0` |
| `cal_i1_ref` | 16 | signed | Stored I reference for prepared \|1> | `0` |
| `cal_q1_ref` | 16 | signed | Stored Q reference for prepared \|1> | `0` |
| `cal_i_threshold` | 16 | signed | Threshold derived from \|0> and \|1> I references | `0` |
| `cal_state_polarity` | 1 | status | Indicates which side of the threshold corresponds to state `1` | `0` |
| `cal_i0q0_valid` | 1 | status | \|0> reference valid | `0` |
| `cal_i1q1_valid` | 1 | status | \|1> reference valid | `0` |
| `cal_threshold_valid` | 1 | status | Threshold valid | `0` |
| `meas_state` | 1 | status | Thresholded measurement state result | `0` |
| `meas_state_valid` | 1 | status | High when `meas_state` is valid | `0` |
| `cal_debug_update_pulse` | 1 | debug pulse | Pulses when calibration references are updated | `0` |
| `cal_debug_ref0_sel` | 1 | debug status | `1` when the last calibration write targeted \|0>, else \|1> | `0` |

## Control Register Write Packet

The control register is written over UART using packet type `0x10`.
The control flags byte uses the following bit assignments:

| Bit | Name | Description |
|---:|---|---|
| 0 | `start_exp` | Start experiment |
| 1 | `soft_reset_req` | Request soft reset |
| 2 | `read_all_pulse` | Request full dump/readback |

## Play Configuration Memory

Each play configuration entry is a packed `play_cfg_t` structure:

| Field | Width | Type | Description |
|---|---:|---|---|
| `amp_q8_8` | 16 | unsigned Q8.8 | Pulse amplitude |
| `phase_q8_8` | 16 | unsigned Q8.8 | Pulse phase |
| `duration_ns` | 32 | unsigned | Pulse duration in ns |
| `sigma_ns` | 32 | unsigned | Gaussian sigma in ns |
| `pad_ns` | 32 | unsigned | Zero-padding / trailing pad in ns |
| `detune_hz` | 32 | unsigned | Frequency detune in Hz |
| `envelope` | 4 | enum | `ENV_SQUARE=0`, `ENV_GAUSS=1` |

### Play Config Address Space

- Valid indices: `0..15`
- Valid bit is set when an entry is written

## Measure Configuration Memory

Each measure configuration entry is a packed `measure_cfg_t` structure:

| Field | Width | Type | Description |
|---|---:|---|---|
| `n_readout` | 16 | unsigned | Number of readout samples / points |
| `readout_ns` | 32 | unsigned | Readout window in ns |
| `ringup_ns` | 32 | unsigned | Resonator ring-up time in ns |

### Measure Config Address Space

- Valid indices: `0..3`
- Valid bit is set when an entry is written

## Instruction Memory

Each instruction memory entry is a packed `instr_t` structure:

| Field | Width | Description |
|---|---:|---|
| `opcode` | 4 | Operation code |
| `flags` | 4 | Reserved for future use in current RTL |
| `cfg_index` | 4 | Play/measure config index when relevant |
| `operand` | 20 | Opcode-specific operand |

### Instruction Address Space

- Valid indices: `0..31`
- Valid bit is set when an entry is written

See [Instruction Set](instruction_set.md) for opcode semantics.

## UART Write Formats

### Play Config Write Packet (`0x12`)

Payload order after sync/type:

1. `addr`
2. `amp_q8_8[7:0]`
3. `amp_q8_8[15:8]`
4. `phase_q8_8[7:0]`
5. `phase_q8_8[15:8]`
6. `duration_ns[7:0]`
7. `duration_ns[15:8]`
8. `duration_ns[23:16]`
9. `duration_ns[31:24]`
10. `sigma_ns[7:0]`
11. `sigma_ns[15:8]`
12. `sigma_ns[23:16]`
13. `sigma_ns[31:24]`
14. `pad_ns[7:0]`
15. `pad_ns[15:8]`
16. `pad_ns[23:16]`
17. `pad_ns[31:24]`
18. `detune_hz[7:0]`
19. `detune_hz[15:8]`
20. `detune_hz[23:16]`
21. `detune_hz[31:24]`
22. `envelope`

### Measure Config Write Packet (`0x13`)

Payload order after sync/type:

1. `addr`
2. `n_readout[7:0]`
3. `n_readout[15:8]`
4. `readout_ns[7:0]`
5. `readout_ns[15:8]`
6. `readout_ns[23:16]`
7. `readout_ns[31:24]`
8. `ringup_ns[7:0]`
9. `ringup_ns[15:8]`
10. `ringup_ns[23:16]`
11. `ringup_ns[31:24]`

### Instruction Write Packet (`0x14`)

Payload order after sync/type:

1. `addr`
2. `instr_word[7:0]`
3. `instr_word[15:8]`
4. `instr_word[23:16]`
5. `instr_word[31:24]`

Instruction words are written little-endian on the UART and unpack into:

```text
[31:28] opcode
[27:24] flags
[23:20] cfg_index
[19:0]  operand
```

## Default ROM Initialization

`defaults_rom.sv` preloads a small default experiment when `LoadDefaultsAfterReset` is enabled.

### Default Play Config Entries

| Entry | `amp_q8_8` | `phase_q8_8` | `duration_ns` | `sigma_ns` | `pad_ns` | `detune_hz` | `envelope` | Notes |
|---:|---:|---:|---:|---:|---:|---:|---|---|
| 0 | `0x0100` | `0x0000` | 200 | 30 | 200 | 0 | `ENV_GAUSS` | Nominal pulse |
| 1 | `0x0330` | `0x0000` | 200 | 30 | 200 | 0 | `ENV_GAUSS` | Stronger \|1> prep candidate |
| 2 | `0x0080` | `0x0100` | 200 | 30 | 200 | 0 | `ENV_GAUSS` | Secondary test pulse |

All other play config entries remain invalid until explicitly written.

### Default Measure Config Entries

| Entry | `n_readout` | `readout_ns` | `ringup_ns` | Notes |
|---:|---:|---:|---:|---|
| 0 | 64 | 1024 | 512 | Default measurement window |
| 1 | 64 | 1024 | 256 | Shorter ring-up |

All other measure config entries remain invalid until explicitly written.

### Default Scalar Register Preload

| Register | Value |
|---|---:|
| `reset_wait_cycles` | `1000` |

### Default Instruction ROM Stream

| Instr addr | Opcode | `cfg_index` | `operand` | Meaning |
|---:|---|---:|---:|---|
| 0 | `ACCUM_CLEAR` | 0 | 0 | Clear accumulator before \|0> calibration |
| 1 | `WAIT_RESET` | 0 | 0 | Wait reset interval before \|0> calibration shot |
| 2 | `MEASURE` | 0 | 0 | Measure with measure config 0 |
| 3 | `ACCUM` | 0 | 0 | Accumulate measured `I_avg/Q_avg` |
| 4 | `LOOP` | 0 | `0x00201` | Repeat instruction 1 body for 3 total passes |
| 5 | `ACCUM_AVG` | 0 | `1` | Store average to \|0> references |
| 6 | `ACCUM_CLEAR` | 0 | 0 | Clear accumulator before \|1> calibration |
| 7 | `WAIT_RESET` | 0 | 0 | Wait reset interval before \|1> calibration shot |
| 8 | `PLAY` | 1 | 0 | Apply play config 1 to prepare \|1> |
| 9 | `MEASURE` | 1 | 0 | Measure with measure config 1 |
| 10 | `ACCUM` | 0 | 0 | Accumulate measured `I_avg/Q_avg` |
| 11 | `LOOP` | 0 | `0x00207` | Repeat instruction 7 body for 3 total passes |
| 12 | `ACCUM_AVG` | 0 | `2` | Store average to \|1> references |
| 13 | `WAIT_RESET` | 0 | 0 | Reset before test sequence |
| 14 | `PLAY` | 0 | 0 | Apply play config 0 |
| 15 | `WAIT` | 0 | 100 | Wait 100 cycles |
| 16 | `PLAY` | 2 | 0 | Apply play config 2 |
| 17 | `MEASURE` | 0 | 0 | Measure with measure config 0 |
| 18 | `END` | 0 | 0 | End sequence |

## Notes

- Calibration thresholding currently uses the **I** average and not the Q average.
- `cal_i_threshold` is computed as the midpoint between the stored `|0>` and `|1>` I references.
- `cal_state_polarity` records whether larger-I values correspond to logic state `1`.
