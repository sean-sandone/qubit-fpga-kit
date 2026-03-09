import json
import time
import struct
import numpy as np
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional

import serial  # pip install pyserial

from qubit_sim.virtual_fpga import VirtualFPGA
from qubit_sim.qubit_model import QubitSim


def _safe_float(x, default=0.0) -> float:
    try:
        return float(x)
    except Exception:
        return float(default)


def _ts() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]


def _debug_log(
    msg: str,
    *,
    debug: bool = False,
    log_path: Optional[Path] = None,
) -> None:
    if not debug and log_path is None:
        return

    line = f"[{_ts()}] {msg}"

    if debug:
        print(line, flush=True)

    if log_path is not None:
        with log_path.open("a", encoding="utf-8") as f:
            f.write(line + "\n")


def _avg(xs) -> float:
    if not xs:
        return 0.0
    return float(sum(xs) / len(xs))


def _build_tx_terminal_summary(resp: Dict[str, Any]) -> str:
    """
    Build a compact one-line TX summary for terminal debug output.
    Keep full arrays out of the terminal, but still show useful stats.
    """
    if not isinstance(resp, dict):
        return f"TX {resp}"

    if not resp.get("ok", False):
        return f"TX {json.dumps(resp)}"

    i_vals = resp.get("I")
    q_vals = resp.get("Q")
    n = resp.get("n")

    if isinstance(i_vals, list) and isinstance(q_vals, list):
        i_avg = _avg(i_vals)
        q_avg = _avg(q_vals)
        i_min = min(i_vals) if i_vals else 0.0
        i_max = max(i_vals) if i_vals else 0.0
        q_min = min(q_vals) if q_vals else 0.0
        q_max = max(q_vals) if q_vals else 0.0

        return (
            "TX "
            f'{{"ok": true, "n": {int(n) if n is not None else len(i_vals)}, '
            f'"I_avg": {i_avg:.6f}, "Q_avg": {q_avg:.6f}, '
            f'"I_min": {i_min:.6f}, "I_max": {i_max:.6f}, '
            f'"Q_min": {q_min:.6f}, "Q_max": {q_max:.6f}}}'
        )

    return f"TX {json.dumps(resp)}"


def handle_cmd(obj: Dict[str, Any], fpga: VirtualFPGA, sim: QubitSim) -> Dict[str, Any]:
    """
    Expected request (one JSON object per line):
      {"cmd":"PLAY", "amp":1.0, "phase":0.0, "duration_s":200e-9, "envelope":"gauss", "sigma_s":30e-9,
       "pad_s":200e-9, "n_readout":64, "readout_duration_s":1.0e-6}

    Response:
      {"ok":true, "n":64, "t_ro_s":[...], "I":[...], "Q":[...]}
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
    n_readout = int(obj.get("n_readout", 64))
    readout_duration_s = _safe_float(obj.get("readout_duration_s", 1.0e-6))
    ringup_fraction = _safe_float(obj.get("ringup_fraction", 0.2))

    t, env, Iw, Qw = fpga.render_iq(pulse, pad_s=pad_s)
    t_ro, I_ro, Q_ro = sim.measure_waveform_from_iq(
        t,
        Iw,
        Qw,
        if_hz=fpga.if_hz,
        detuning_hz=detuning_hz,
        n_readout=n_readout,
        readout_duration_s=readout_duration_s,
        ringup_fraction=ringup_fraction,
    )

    return {
        "ok": True,
        "n": int(len(t_ro)),
        "t_ro_s": [float(x) for x in t_ro],
        "I": [float(x) for x in I_ro],
        "Q": [float(x) for x in Q_ro],
    }


def _clip_i16(x: int) -> int:
    if x > 32767:
        return 32767
    if x < -32768:
        return -32768
    return x


def float_iq_to_interleaved_i16_bytes(I_vals, Q_vals, scale: float = 32767.0) -> bytes:
    """
    Convert float I/Q arrays to interleaved little-endian int16 bytes:
      I0, Q0, I1, Q1, ...

    Example output layout for one sample pair:
      I0_lo I0_hi Q0_lo Q0_hi
    """
    if len(I_vals) != len(Q_vals):
        raise ValueError("I and Q arrays must have the same length")

    packed = bytearray()
    for i_f, q_f in zip(I_vals, Q_vals):
        i_i16 = _clip_i16(int(round(float(i_f) * scale)))
        q_i16 = _clip_i16(int(round(float(q_f) * scale)))
        packed += struct.pack("<hh", i_i16, q_i16)
    return bytes(packed)


def build_waveform_packet(I_vals, Q_vals, scale: float = 32767.0) -> bytes:
    """
    Build a binary packet:
      [0xA5][0x5A][0x02][N][interleaved int16 IQ bytes]

    N is the number of IQ pairs and must fit in one byte.
    """
    n = len(I_vals)
    if len(Q_vals) != n:
        raise ValueError("I and Q arrays must have the same length")
    if n > 255:
        raise ValueError("n_readout must be <= 255 for 1-byte sample count")

    payload = float_iq_to_interleaved_i16_bytes(I_vals, Q_vals, scale=scale)
    header = bytes([0xA5, 0x5A, 0x02, n])
    return header + payload


def run_uart_server(
    port: str,
    baud: int = 115200,
    fs_hz: float = 250e6,
    if_hz: float = 50e6,
    omega_max_hz: float = 2e6,
    timeout_s: float = 0.2,
    debug: bool = False,
    log_file: str | None = None,
):
    fpga = VirtualFPGA(fs_hz=fs_hz, if_hz=if_hz)
    sim = QubitSim(seed=1, omega_max_hz=omega_max_hz)

    log_path = Path(log_file) if log_file else None

    _debug_log(
        f"Opening serial port port={port} baud={baud} timeout_s={timeout_s}",
        debug=debug,
        log_path=log_path,
    )

    with serial.Serial(port, baudrate=baud, timeout=timeout_s) as ser:
        time.sleep(0.05)

        _debug_log("Serial port opened", debug=debug, log_path=log_path)

        while True:
            line = ser.readline()
            if not line:
                continue

            rx_text = line.decode("utf-8", errors="replace").strip()
            _debug_log(f"RX {rx_text}", debug=debug, log_path=log_path)

            try:
                obj = json.loads(rx_text)
                resp = handle_cmd(obj, fpga, sim)
            except Exception as e:
                resp = {"ok": False, "err": str(e)}

            if resp.get("ok") and isinstance(resp.get("I"), list) and isinstance(resp.get("Q"), list):
                # Terminal: compact summary
                if debug:
                    _debug_log(
                        _build_tx_terminal_summary(resp),
                        debug=True,
                        log_path=None,
                    )

                # File: full JSON for debugging
                if log_path is not None:
                    _debug_log(
                        f"TX {json.dumps(resp)}",
                        debug=False,
                        log_path=log_path,
                    )

                # Binary packet to FPGA
                tx_packet = build_waveform_packet(resp["I"], resp["Q"], scale=32767.0)

                # File: exact binary payload as hex
                if log_path is not None:
                    hex_dump = tx_packet.hex(" ")
                    _debug_log(
                        f"TX_BIN_HEX {hex_dump}",
                        debug=False,
                        log_path=log_path,
                    )

                ser.write(tx_packet)
                ser.flush()

                if debug:
                    _debug_log(
                        f"TX_BIN bytes={len(tx_packet)} sync=A5 5A type=02 n={resp['n']}",
                        debug=True,
                        log_path=None,
                    )

                if log_path is not None:
                    _debug_log(
                        f"TX_BIN bytes={len(tx_packet)} sync=A5 5A type=02 n={resp['n']}",
                        debug=False,
                        log_path=log_path,
                    )
            else:
                # Keep non-waveform responses as JSON text
                tx_text = json.dumps(resp)

                if debug:
                    _debug_log(
                        f"TX {tx_text}",
                        debug=True,
                        log_path=None,
                    )

                if log_path is not None:
                    _debug_log(
                        f"TX {tx_text}",
                        debug=False,
                        log_path=log_path,
                    )

                ser.write((tx_text + "\n").encode("utf-8"))
                ser.flush()


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True, help="COM3, COM4, /dev/ttyUSB0, etc")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--fs_hz", type=float, default=250e6)
    ap.add_argument("--if_hz", type=float, default=50e6)
    ap.add_argument("--omega_max_hz", type=float, default=2e6)
    ap.add_argument("--timeout_s", type=float, default=0.2)
    ap.add_argument("--debug", action="store_true", help="Print RX/TX debug info to terminal")
    ap.add_argument("--log_file", default=None, help="Optional log file path")
    args = ap.parse_args()

    run_uart_server(
        port=args.port,
        baud=args.baud,
        fs_hz=args.fs_hz,
        if_hz=args.if_hz,
        omega_max_hz=args.omega_max_hz,
        timeout_s=args.timeout_s,
        debug=args.debug,
        log_file=args.log_file,
    )