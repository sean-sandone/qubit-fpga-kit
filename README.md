# Quantum Computing FPGA Qubit Controller & Test Environment

This project is an FPGA-based qubit-control and experimentation platform built using a Xilinx evaluation board and a host PC running QuTiP simulations. It provides a practical environment for developing and testing pulse sequencing, measurement, calibration, and control-loop behavior using real FPGA hardware and QuTiP qubit simulations.

The system is designed to keep setup simple and low cost, requiring only a USB/UART link between the FPGA and the host. To support easy bring-up and debugging, the hardware can generate human-readable JSON debug output that can be monitored with your favorite serial terminal software or the included Python tools. An intuitive browser-based web UI and a command-line menu interface are provided for loading register values, programming instruction memory, calibrating |0> and |1> reference states, and running experiments.

![qubit-fpga-kit top level block diagram](docs/diagrams/qu%20control.drawio.svg)

## Requirements

- Python 3.10+
- A Xilinx FPGA evaluation board with onboard UART USB interface
- A USB/UART connection between the FPGA board and host PC

## Setup

### 1. Clone the repository

```bash
git clone https://github.com/sean-sandone/qubit-fpga-kit.git
cd qubit-fpga-kit
```

### 2. Create or activate a Python environment with QuTiP support

Use a Python environment that has QuTiP installed and will be used to run the host software.

Example with conda:

```bash
conda create -n qutip python=3.11
conda activate qutip
```

If you already have a working QuTiP environment, activate that instead.

### 3. Install Python dependencies

Install the required Python packages:

```bash
pip install numpy qutip pyserial flask matplotlib
```

### 4. Install the project package

From the repository root, install the project in editable mode:

```bash
pip install -e .
```

This is recommended because the host application is launched as a Python module:

```bash
python -m qubit_sim.uart_server --port COM<your port #> --debug --log_file <log file name> --ui --ui_host 127.0.0.1 --ui_port 5000
```

### 5. Connect the FPGA hardware

You will need:

- A Xilinx FPGA evaluation board programmed with the project bitstream and using the onboard UART interface
- This project is built on the KCU105 evaluation board but can be run on any FPGA board with a UART/USB interface by simply updating the pinout constraints for your board
- A USB connection between the FPGA board and the host PC
- The UART serial port driver for your system and associated COM port

### 6. Run the host software

Start the UART server with your FPGA serial port:

```bash
python -m qubit_sim.uart_server --port COM<your port #> --debug --log_file <log file name> --ui --ui_host 127.0.0.1 --ui_port 5000
```

Useful command-line options include:

- `--baud` default `115200`
- `--fs_hz` default `250e6`
- `--if_hz` default `50e6`
- `--omega_max_hz` default `2e6`
- `--timeout_s` default `0.2`
- `--debug`
- `--log_file <path>`
- `--ui`
- `--ui_host` default `127.0.0.1`
- `--ui_port` default `5000`

Example with debug logging and the web UI enabled:

```bash
python -m qubit_sim.uart_server --port COM6 --debug --log_file test.log --ui --ui_host 127.0.0.1 --ui_port 5000
```

### 7. Use the command-line menu

When the UART server is running, press:

```text
m
```

to open the interactive UART menu.

The menu supports:

- showing the current register summary
- writing control, reset-wait, play, measure, and instruction values
- requesting a register dump
- batch sending all writable registers
- starting an experiment
- saving and loading JSON config files

### 8. Use the web UI

If started with `--ui`, the web UI binds by default to:

```text
http://127.0.0.1:5000
```

The UI provides:

- live mirrored register and control state
- editable play config, measure config, and instruction memory fields
- generated waveform previews
- experiment result plots
- JSON config save/load actions

### 9. JSON config files

The host software supports saving and loading configuration data as JSON. The default path used in both the menu and web UI is:

```text
config/qubit_fpga_config.json
```

Loading a JSON config updates the local shadow values and sends writable registers back to the FPGA.

## Notes

- The host-side Virtual FPGA expands compact pulse descriptions into DAC-style I/Q waveforms rather than requiring the FPGA to stream fully sampled waveforms over UART.
- The qubit simulator converts those I/Q waveforms into a baseband complex envelope and evolves the qubit state in QuTiP.
- The UART text command path currently supports `PING`, `RESET`, `PLAY`, and `MEASURE`. `PLAY` renders and applies a pulse, while `MEASURE` returns readout waveform samples.
- Returned readout waveform data is packed into a binary UART packet using interleaved signed Q2.14 I/Q samples with header `[0xA5][0x5A][0x02][N]`.

## Documentation

- [Theory of Operation](docs/theory_of_operation.md)
- [Register Map](docs/register_map.md)
- [Instruction Set](docs/instruction_set.md)