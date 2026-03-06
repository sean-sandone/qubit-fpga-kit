import json
import time
from typing import Any, Dict

import serial  # pip install pyserial

from qubit_sim.virtual_fpga import VirtualFPGA
from qubit_sim.qubit_model import QubitSim


def _safe_float(x, default=0.0) -> float:
    try:
        return float(x)
    except Exception:
        return float(default)


def handle_cmd(obj: Dict[str, Any], fpga: VirtualFPGA, sim: QubitSim) -> Dict[str, Any]:
    """
    Expected request (one JSON object per line):
      {"cmd":"PLAY", "amp":1.0, "phase":0.0, "duration_s":200e-9, "envelope":"gauss", "sigma_s":30e-9, "pad_s":200e-9}

    Response:
      {"ok":true, "I":..., "Q":..., "p1":...}   (p1 optional)
    """
    cmd = str(obj.get("cmd", "")).upper()

    if cmd == "PING":
        return {"ok": True, "msg": "PONG"}

    if cmd != "PLAY":
        return {"ok": False, "err": f"Unknown cmd {cmd!r}"}

    pulse = {
        "amp": _safe_float(obj.get("amp", 0.0)),
        "phase": _safe_float(obj.get("phase", 0.0)),
        "duration": _safe_float(obj.get("duration_s", 0.0)),
        "envelope": str(obj.get("envelope", "square")),
    }
    if "sigma_s" in obj and obj["sigma_s"] is not None:
        pulse["sigma"] = _safe_float(obj["sigma_s"])

    pad_s = _safe_float(obj.get("pad_s", 0.0))
    detuning_hz = _safe_float(obj.get("detuning_hz", 0.0))

    # Generate DAC-style I/Q and run the qubit measurement
    t, env, Iw, Qw = fpga.render_iq(pulse, pad_s=pad_s)
    I_meas, Q_meas = sim.measure_from_iq(t, Iw, Qw, if_hz=fpga.if_hz, detuning_hz=detuning_hz)

    return {"ok": True, "I": float(I_meas), "Q": float(Q_meas)}


def run_uart_server(
    port: str,
    baud: int = 115200,
    fs_hz: float = 250e6,
    if_hz: float = 50e6,
    omega_max_hz: float = 2e6,
    timeout_s: float = 0.2,
):
    fpga = VirtualFPGA(fs_hz=fs_hz, if_hz=if_hz)
    sim = QubitSim(seed=1, omega_max_hz=omega_max_hz)

    with serial.Serial(port, baudrate=baud, timeout=timeout_s) as ser:
        # optional: small settle time after opening the port
        time.sleep(0.05)

        while True:
            line = ser.readline()
            if not line:
                continue

            try:
                obj = json.loads(line.decode("utf-8", errors="replace").strip())
                resp = handle_cmd(obj, fpga, sim)
            except Exception as e:
                resp = {"ok": False, "err": str(e)}

            ser.write((json.dumps(resp) + "\n").encode("utf-8"))
            ser.flush()


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True, help="COM3, COM4, /dev/ttyUSB0, etc")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--fs_hz", type=float, default=250e6)
    ap.add_argument("--if_hz", type=float, default=50e6)
    ap.add_argument("--omega_max_hz", type=float, default=2e6)
    args = ap.parse_args()

    run_uart_server(
        port=args.port,
        baud=args.baud,
        fs_hz=args.fs_hz,
        if_hz=args.if_hz,
        omega_max_hz=args.omega_max_hz,
    )