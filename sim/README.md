# Simulation Testbench

## Overview

This directory contains simulation-only files for the `qubit-fpga-kit` project.

The first testbench, `qu_control_top_tb.sv`, is a simple top-level smoke test for the FPGA design. It verifies that after reset is released, the design completes its startup initialization and begins transmitting the first UART command.

For the current default startup ROM contents, the first transmitted command should be:

```json
{"cmd":"RESET"}
```

So the first UART character expected from the DUT is:

```text
{
```

## Why This Testbench Is Enough

This design sends human-readable debug and command traffic over UART. Because of that, only a simple smoke test is needed in simulation to confirm that the UART transmit path is alive and working.

Once the design is shown to:
- come out of reset
- complete its startup initialization
- begin transmitting the expected UART output

the higher-level behavior is usually easier and more meaningful to debug on real hardware, where the full UART stream can be observed directly from the host side.

In other words, this testbench is mainly intended to answer:

> Does the design start up correctly and begin transmitting readable UART output?

If yes, then deeper debug is done on the FPGA with the existing hardware/software flow.

## Testbench Summary

`qu_control_top_tb.sv` is a bring-up smoke test for `qu_control_top`.

It performs the following checks:

1. Generates the DUT clock
2. Holds reset active briefly
3. Releases reset
4. Allows the design to load its default register and instruction contents from ROM
5. Waits for the DUT to begin UART transmission
6. Decodes the first transmitted UART byte
7. Passes if the first byte is `{`

This confirms that the following major pieces of the startup path are functioning:

- top-level reset handling
- reset synchronization
- default ROM loading
- instruction sequencer auto-start after initialization
- command formatter startup
- UART transmit path

Because the design already emits human-readable UART traffic, this smoke test is sufficient to confirm the UART transmit path is working. Higher-level debug is generally better done with real hardware and the existing host-side software, where the full UART command and debug stream can be observed directly.

## Files

- `tb/qu_control_top_tb.sv`  
  Top-level SystemVerilog simulation testbench for `qu_control_top`

## Running in Vivado

### 1. Add sources

Add the following files to the Vivado project:

- all synthesizable RTL files under `rtl/`
- `sim/tb/qu_control_top_tb.sv` as a **Simulation Source**

### 2. Set the simulation top

Set the simulation top to:

```text
qu_control_top_tb
```

### 3. Launch behavioral simulation

In Vivado:

- **Flow Navigator -> Simulation -> Run Simulation -> Run Behavioral Simulation**

If Vivado only runs for the default `1000ns`, restart and run longer from the Tcl console:

```tcl
restart
run all
```

or:

```tcl
restart
run 2 ms
```

## Expected Result

A successful run should print a message similar to:

```text
[time] Released reset
[time] First UART byte = 0x7b ({)
[time] PASS: DUT transmitted '{' as first UART byte
```

If the DUT does not begin UART transmission before the timeout, the testbench will fail with a fatal timeout message.

## Startup Behavior Checked by This Test

The startup sequence exercised by this testbench is:

- reset released
- internal reset synchronizer settles
- `init_loader` loads default values from `defaults_rom`
- ROM reaches `INIT_OP_END`
- `init_done_pulse` starts the instruction sequencer
- default instruction stream begins executing
- first formatted command is `RESET`
- UART begins transmitting `{"cmd":"RESET"}`

The configured `reset_wait_cycles` value does not delay the first transmitted `{`. That wait occurs after the reset command has already been transmitted.

## Scope

This is intentionally a simple smoke test. It does not attempt to fully verify:

- the complete transmitted command string
- host-to-FPGA UART receive behavior
- register write command handling
- measurement response handling
- calibration loop behavior
- full instruction execution coverage
- long experiment sequences

That level of debug is not the main goal here.

Because the design already emits human-readable UART traffic, once the transmit path is confirmed working in simulation, most higher-level debug can be done more effectively on real hardware using the existing host software and UART logs.

