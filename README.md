# Quantum Computing FPGA Qubit Controller & Test Environment

A FPGA based Quantum Computing Qubit Controller test and expirmentation suite using a Xilinx evaulation board and PC or server running QuTIP qubit simulations. Features simple communcation between FPGA and qubit simualtion via USB/UART connection.  The RTL (FPGA based logic) can send humnan readable JSON debug strings for easy bring-up and debug by just monitoring a com port with terminal software or included, custom python software.  Simple menu based UI for loading registers, instruction memory, calibrating |0> & |1> states, and running expirments.

![qubit-fpga-kit top level block diagram](docs/diagrams/qu%20control.drawio.svg)

## Setup

Coming Soon

## Running Expirments

From the `sw\qubit_sim\src directory` 
run `python -m qubit_sim.uart_server --port COM<com port #> --debug --log_file <logfile name>`

## Register Map

> Note: this design currently uses a **logical register bank plus small config/instruction memories**, not a flat memory-mapped address space.  
> Play config, measure config, and instruction entries are written by index.  
> Control updates are also supported over UART packet types `0x10` to `0x14`.

### Control and Status Registers

| Register / Signal | Width | Access | Description |
|---|---:|---|---|
| `start_exp` | 1 | W / R | Start experiment request. Set by control write. Cleared by sequencer handshake (`clear_start_exp`). |
| `soft_reset_req` | 1 | W pulse / R | Soft reset request pulse generated from control write. |
| `reset_wait_cycles` | 32 | W / R | Default wait used by `OP_WAIT_RESET` after issuing the reset command to the PC/Qutip side. |
| `seq_busy` | 1 | R | Sequencer busy status. High while an experiment program is running. |
| `seq_done_sticky` | 1 | R | Sticky done flag. Set when the sequencer reaches `OP_END`. Cleared when a new experiment is started. |
| `play_cfg_any_valid` | 1 | R | High if any play configuration slot has been written. |
| `measure_cfg_any_valid` | 1 | R | High if any measure configuration slot has been written. |
| `instr_any_valid` | 1 | R | High if any instruction slot has been written. |

### Calibration Result Registers

| Register / Signal | Width | Access | Description |
|---|---:|---|---|
| `cal_sample_count` | 16 | R | Number of samples accumulated for the most recent calibration average result. |
| `cal_i_avg` | 16 signed | R | Most recent calibration average I result. |
| `cal_q_avg` | 16 signed | R | Most recent calibration average Q result. |
| `cal_i0_ref` | 16 signed | R | Stored calibration I reference for the `|0>` state. |
| `cal_q0_ref` | 16 signed | R | Stored calibration Q reference for the `|0>` state. |
| `cal_i1_ref` | 16 signed | R | Stored calibration I reference for the `|1>` state. |
| `cal_q1_ref` | 16 signed | R | Stored calibration Q reference for the `|1>` state. |
| `cal_i_threshold` | 16 signed | R | Threshold derived from the midpoint of `cal_i0_ref` and `cal_i1_ref`. |
| `cal_state_polarity` | 1 | R | Comparison polarity used for state classification. `1` means `I >= threshold` maps to `|1>`, `0` means `I < threshold` maps to `|1>`. |
| `cal_i0q0_valid` | 1 | R | High once the `|0>` calibration reference has been captured. |
| `cal_i1q1_valid` | 1 | R | High once the `|1>` calibration reference has been captured. |
| `cal_threshold_valid` | 1 | R | High once both references exist and the threshold has been computed. |

### Measurement State Registers

| Register / Signal | Width | Access | Description |
|---|---:|---|---|
| `meas_state` | 1 | R | Classified measurement state from the latest measurement, based on `meas_i_avg_in` and the calibration threshold. |
| `meas_state_valid` | 1 | R | High when `meas_state` is valid. Cleared by `clear_meas_state_valid`. |

### Calibration Debug Registers / Pulses

| Register / Signal | Width | Access | Description |
|---|---:|---|---|
| `cal_debug_update_pulse` | 1 | R pulse | Pulses when a calibration reference register is updated. |
| `cal_debug_ref0_sel` | 1 | R | Indicates which reference was most recently updated. `1 = ref0`, `0 = ref1`. |

---

## Play Configuration Memory

Depth: **8 entries** (`PlayCfgDepth = 8`)

Each entry is a `play_cfg_t`.

| Field | Width | Description |
|---|---:|---|
| `amp_q8_8` | 16 | Pulse amplitude in Q8.8 fixed-point format. |
| `phase_q8_8` | 16 | Pulse phase in Q8.8 fixed-point format. |
| `duration_ns` | 32 | Pulse duration in ns. |
| `sigma_ns` | 32 | Gaussian sigma in ns. |
| `pad_ns` | 32 | Extra padding time in ns. |
| `detune_hz` | 32 | Frequency detune in Hz. |
| `envelope` | 4 | Envelope type. `0 = SQUARE`, `1 = GAUSS`. |

---

## Measure Configuration Memory

Depth: **4 entries** (`MeasCfgDepth = 4`)

Each entry is a `measure_cfg_t`.

| Field | Width | Description |
|---|---:|---|
| `n_readout` | 16 | Number of downsampled readout samples expected. |
| `readout_ns` | 32 | Readout duration in ns. |
| `ringup_ns` | 32 | Readout ring-up time in ns. |

---

## Instruction Memory

Depth: **32 entries** (`InstrDepth = 32`)

Each entry is an `instr_t`.

| Field | Width | Description |
|---|---:|---|
| `opcode` | 4 | Instruction opcode. |
| `flags` | 4 | Reserved for future use. Present in the instruction format but not currently used by the sequencer logic. |
| `cfg_index` | 4 | Selects the play or measure config entry used by the instruction. |
| `operand` | 20 | Opcode-specific operand field. |

---

## Instruction Set

| Opcode | Value | Uses `cfg_index` | Uses `operand` | Description |
|---|---:|---:|---:|---|
| `OP_NOP` | `0` | No | No | No operation. Advances to the next instruction. |
| `OP_PLAY` | `1` | Yes | No | Sends a `PLAY` command to the PC/Qutip side using the selected play config. |
| `OP_MEASURE` | `2` | Yes | No | Sends a `MEASURE` command using the selected measure config and waits for a measurement response packet. |
| `OP_WAIT` | `3` | No | Yes | Waits for `operand` clock cycles. If `operand == 0`, it behaves like a no-op. |
| `OP_END` | `4` | No | No | Ends the program and raises the sequencer done pulse. |
| `OP_JUMP` | `5` | No | Yes | Sets the program counter to `operand[InstrAw-1:0]`. |
| `OP_WAIT_RESET` | `6` | No | No | Sends a reset command to the PC/Qutip side, then waits for `reset_wait_cycles`. |
| `OP_ACCUM_CLEAR` | `7` | No | No | Clears the calibration accumulator state. |
| `OP_ACCUM` | `8` | No | No | Pushes the latest measured I/Q average into the calibration accumulator. |
| `OP_ACCUM_AVG` | `9` | No | Yes | Finalizes the calibration accumulator average and stores the result according to `operand[1:0]`. |
| `OP_LOOP` | `10` | No | Yes | Loop control. On first encounter, loads loop count from `operand[19:8]` and target PC from the low instruction address bits, then branches to the target. Repeats until the loop count expires. |

### Opcode Operand Encoding Notes

| Opcode | Operand Encoding |
|---|---|
| `OP_WAIT` | `operand = wait_cycles` |
| `OP_JUMP` | `operand[InstrAw-1:0] = target_instruction_address` |
| `OP_ACCUM_AVG` | `operand[1:0]` selects destination: `0 = TEMP`, `1 = REF0`, `2 = REF1` |
| `OP_LOOP` | `operand[19:8] = loop_count`, low instruction address bits = loop target address |

---

## UART Register Write Packet Types

These packet types are decoded by `write_reg_rx` and drive updates into the register bank.

| Packet Type | Value | Payload | Effect |
|---|---:|---|---|
| `RegWrTypeControl` | `0x10` | 1 byte | Control bits: bit 0 = `start_exp`, bit 1 = `soft_reset` |
| `RegWrTypeResetWait` | `0x11` | 4 bytes LE | Writes `reset_wait_cycles` |
| `RegWrTypePlayCfg` | `0x12` | `addr(1) + amp(2) + phase(2) + duration(4) + sigma(4) + pad(4) + detune(4) + envelope(1)` | Writes one play config entry |
| `RegWrTypeMeasureCfg` | `0x13` | `addr(1) + n_readout(2) + readout_ns(4) + ringup_ns(4)` | Writes one measure config entry |
| `RegWrTypeInstr` | `0x14` | `addr(1) + instr_word(4)` | Writes one instruction entry |

---

## Default Power-Up Contents

When `LoadDefaultsAfterReset = 1`, the init loader preloads the register bank and memories from `defaults_rom`.

### Default Play Configs

| Index | Summary |
|---:|---|
| `0` | Gaussian pulse, amp `0x0100` (1.0), phase `0x0000`, duration `200 ns`, sigma `30 ns`, pad `200 ns`, detune `0 Hz` |
| `1` | Gaussian pulse, amp `0x0330` (3.1875), phase `0x0000`, duration `200 ns`, sigma `30 ns`, pad `200 ns`, detune `0 Hz` |
| `2` | Gaussian pulse, amp `0x0080` (0.5), phase `0x0100`, duration `200 ns`, sigma `30 ns`, pad `200 ns`, detune `0 Hz` |

### Default Measure Configs

| Index | Summary |
|---:|---|
| `0` | `n_readout = 64`, `readout_ns = 1024`, `ringup_ns = 512` |
| `1` | `n_readout = 64`, `readout_ns = 1024`, `ringup_ns = 256` |

### Default Reset Wait

| Register | Value |
|---|---:|
| `reset_wait_cycles` | `1000` |

### Default Instruction Program

| Addr | Instruction | Summary |
|---:|---|---|
| `0` | `ACCUM_CLEAR` | Clear accumulator before `|0>` calibration |
| `1` | `WAIT_RESET` | Reset / wait before `|0>` measurement |
| `2` | `MEASURE cfg=0` | Measure `|0>` reference |
| `3` | `ACCUM` | Accumulate the result |
| `4` | `LOOP operand=0x00201` | Repeat body starting at addr `1` |
| `5` | `ACCUM_AVG operand=1` | Store average into `REF0` |
| `6` | `ACCUM_CLEAR` | Clear accumulator before `|1>` calibration |
| `7` | `WAIT_RESET` | Reset / wait before `|1>` preparation |
| `8` | `PLAY cfg=1` | Apply `|1>` prep pulse |
| `9` | `MEASURE cfg=0` | Measure `|1>` reference |
| `10` | `ACCUM` | Accumulate the result |
| `11` | `LOOP` | Repeat `|1>` calibration body |
| `12` | `ACCUM_AVG operand=2` | Store average into `REF1` |
| `13` | `END` | Finish |