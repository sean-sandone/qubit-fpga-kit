# Instruction Set

Instruction word format and opcode behavior

## Instruction Word Format

Each instruction is a packed 32-bit word:

```text
31          28 27         24 23        20 19                         0
+-------------+-------------+------------+----------------------------+
|   opcode    |    flags    | cfg_index  |          operand           |
+-------------+-------------+------------+----------------------------+
```

### Field Summary

| Field | Bits | Description |
|---|---|---|
| `opcode` | `[31:28]` | Operation code |
| `flags` | `[27:24]` | Reserved in current RTL |
| `cfg_index` | `[23:20]` | Configuration index used by `PLAY` and `MEASURE` |
| `operand` | `[19:0]` | Opcode-specific operand |

## Opcode Map

| Opcode enum | Value | Mnemonic | Description |
|---|---:|---|---|
| `OP_NOP` | `0x0` | `NOP` | No operation |
| `OP_PLAY` | `0x1` | `PLAY` | Start waveform formatting/play path using `cfg_index` |
| `OP_MEASURE` | `0x2` | `MEASURE` | Start measurement path using `cfg_index` |
| `OP_WAIT` | `0x3` | `WAIT` | Delay for `operand` cycles |
| `OP_END` | `0x4` | `END` | End sequence and raise done pulse |
| `OP_JUMP` | `0x5` | `JUMP` | Set program counter to target address in `operand` |
| `OP_WAIT_RESET` | `0x6` | `WAIT_RESET` | Issue reset-style formatting using `reset_wait_cycles` |
| `OP_ACCUM_CLEAR` | `0x7` | `ACCUM_CLEAR` | Clear calibration accumulator |
| `OP_ACCUM` | `0x8` | `ACCUM` | Push latest measurement into calibration accumulator |
| `OP_ACCUM_AVG` | `0x9` | `ACCUM_AVG` | Finalize accumulator and optionally store calibration refs |
| `OP_LOOP` | `0xA` | `LOOP` | Loop back to a prior instruction using encoded repeat count and target |

## Operand Semantics by Opcode

| Opcode | `cfg_index` used | Operand meaning |
|---|---|---|
| `NOP` | No | Ignored |
| `PLAY` | Yes | Ignored in current RTL |
| `MEASURE` | Yes | Ignored in current RTL |
| `WAIT` | No | Number of sequencer wait cycles |
| `END` | No | Ignored |
| `JUMP` | No | Target instruction index in `operand[InstrAw-1:0]` |
| `WAIT_RESET` | No | Ignored, reset duration comes from `reset_wait_cycles` |
| `ACCUM_CLEAR` | No | Ignored |
| `ACCUM` | No | Ignored |
| `ACCUM_AVG` | No | Store destination in `operand[1:0]` |
| `LOOP` | No | Repeat count in `operand[19:8]`, target in low address bits |

## `ACCUM_AVG` Store Destination Encoding

The accumulator finalize/store destination is encoded in `operand[1:0]`:

| Value | Symbol | Meaning |
|---:|---|---|
| `0` | `CAL_DEST_TEMP` | Finalize average without updating \|0> or \|1> references |
| `1` | `CAL_DEST_REF0` | Store finalized average to \|0> reference registers |
| `2` | `CAL_DEST_REF1` | Store finalized average to \|1> reference registers |

## `LOOP` Encoding

`OP_LOOP` uses the 20-bit operand as:

```text
operand[19:8]        = additional repeat count
operand[InstrAw-1:0] = target instruction index
```

With the current build:

- `InstrDepth = 32`
- `InstrAw = 5`
- therefore the loop target uses `operand[4:0]`

### Important behavior

The loop body has already executed once before `OP_LOOP` is decoded.
So the encoded repeat count is the number of **additional** repeats.

That means:

```text
total loop executions = operand[19:8] + 1
```

### Example

`operand = 20'h00201`

- repeat count = `0x002` = 2 additional repeats
- target index = `0x01`
- total executions of the loop body = 3

## Execution Notes by Opcode

### `NOP`

Advances program counter by 1.

### `PLAY`

- Loads `cfg_index` into the sequencer configuration index register
- Marks the formatter transaction as a play operation
- Starts the waveform formatter when it is idle
- Advances after formatting completes

### `MEASURE`

- Loads `cfg_index` into the sequencer configuration index register
- Starts the waveform formatter and measurement path together
- Advances after formatting completes and measurement completes

### `WAIT`

- If `operand == 0`, the instruction is effectively skipped
- Otherwise the sequencer waits `operand` cycles total

### `END`

- Raises `seq_done_pulse`
- Enters done state

### `JUMP`

- Sets `pc` to `operand[InstrAw-1:0]`
- Clears any active loop state

### `WAIT_RESET`

- Marks the formatter transaction as a reset event rather than a play event
- Uses `reset_wait_cycles` rather than the instruction operand for the wait duration
- In the current design, `WAIT_RESET` is used in place of passive qubit relaxation back to \|0>. Rather than modeling natural time-dependent relaxation and dephasing in a standalone wait period, the reset path explicitly forces the simulated qubit back to the ground state.

### `ACCUM_CLEAR`

Clears the calibration accumulator so the next calibration averaging window starts fresh.

### `ACCUM`

Pushes the latest measured average values into the calibration accumulator.

### `ACCUM_AVG`

- Finalizes the accumulated average
- Selects the destination from `operand[1:0]`
- Can update `|0>` or `|1>` reference registers
- When both references are valid, the threshold is computed as the midpoint of the two stored I references

### `LOOP`

- On first encounter, latches repeat count and target
- Branches back to the target while repeats remain
- Falls through when the loop is complete

## UART Write / Read Representation

Instruction words are transported little-endian over UART:

1. low byte first
2. high byte last

So a 32-bit word such as:

```text
0x10200000
```

is sent as bytes:

```text
00 00 20 10
```

## Worked Examples

| Assembly-like form | Encoded word | Notes |
|---|---:|---|
| `PLAY cfg=1` | `0x10100000` | opcode=`1`, cfg=`1`, operand=`0` |
| `MEASURE cfg=0` | `0x20000000` | opcode=`2`, cfg=`0`, operand=`0` |
| `WAIT 100` | `0x30000064` | opcode=`3`, operand=`100` |
| `END` | `0x40000000` | opcode=`4` |
| `ACCUM_CLEAR` | `0x70000000` | opcode=`7` |
| `ACCUM` | `0x80000000` | opcode=`8` |
| `ACCUM_AVG REF0` | `0x90000001` | store destination `1` |
| `ACCUM_AVG REF1` | `0x90000002` | store destination `2` |
| `LOOP repeats=2,target=1` | `0xA0000201` | total body executions = 3 |

## Current Limitations / Reserved Fields

- `flags[3:0]` are defined in the instruction format but are not consumed by the current sequencer logic.
- `PLAY`, `MEASURE`, and `WAIT_RESET` currently ignore the instruction operand.
- `JUMP` and `LOOP` use only the low `InstrAw` bits for target addressing.
