import json
import time
import struct
import math
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional

import serial  # pip install pyserial

from qubit_sim.virtual_fpga import VirtualFPGA
from qubit_sim.qubit_model import QubitSim, iq_to_complex_envelope


AmpFullScale = 0x0100
PhaseTurnScale = 0x10000
NsPerSecond = 1.0e9

# Signed Q2.14 fixed-point format
Q2_14FracBits = 14
Q2_14Scale = 1 << Q2_14FracBits
Q2_14MinFloat = -2.0
Q2_14MaxFloat = (32767.0 / float(Q2_14Scale))  # 1.99993896484375


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


def _parse_int_like(x: Any, default: int = 0) -> int:
    if x is None:
        return int(default)

    if isinstance(x, bool):
        return int(x)

    if isinstance(x, int):
        return int(x)

    if isinstance(x, float):
        return int(x)

    s = str(x).strip()
    if not s:
        return int(default)

    s = s.replace(" ", "").replace("_", "")

    try:
        if s.lower().startswith("0x"):
            return int(s, 16)

        if any(c in "abcdefABCDEF" for c in s):
            return int(s, 16)

        if len(s) > 1 and s.startswith("0"):
            return int(s, 16)

        return int(s, 10)
    except Exception:
        return int(default)


def _u16_to_phase_rad(word: int) -> float:
    return (2.0 * math.pi * float(word & 0xFFFF)) / float(PhaseTurnScale)


def _ns_to_seconds(ns: int) -> float:
    return float(ns) / float(NsPerSecond)


def _decode_play(obj: Dict[str, Any]) -> Dict[str, Any]:
    envelope_raw = str(obj.get("envelope", "SQUARE")).strip().upper()

    amp_word = _parse_int_like(obj.get("amp_q8_8", obj.get("amp", 0)))
    phase_word = _parse_int_like(obj.get("phase_q8_8", obj.get("phase", 0)))

    duration_ns = _parse_int_like(obj.get("duration_ns", obj.get("duration", 0)))
    sigma_ns = _parse_int_like(obj.get("sigma_ns", obj.get("sigma", 0)))
    pad_ns = _parse_int_like(obj.get("pad_ns", obj.get("pad", 0)))
    detune_hz = _parse_int_like(obj.get("detune_hz", obj.get("detune", 0)))

    pulse = {
        "amp": float(amp_word) / float(AmpFullScale),
        "phase": _u16_to_phase_rad(phase_word),
        "duration": _ns_to_seconds(duration_ns),
        "envelope": "gauss" if envelope_raw == "GAUSS" else "square",
    }

    if sigma_ns > 0:
        pulse["sigma"] = _ns_to_seconds(sigma_ns)

    return {
        "pulse": pulse,
        "pad_s": _ns_to_seconds(pad_ns),
        "detuning_hz": float(detune_hz),
    }


def _decode_measure(obj: Dict[str, Any]) -> Dict[str, Any]:
    n_readout = _parse_int_like(obj.get("n_readout", 0x40))
    readout_ns = _parse_int_like(obj.get("readout_ns", obj.get("readout_cycles", 0x80)))
    ringup_ns = _parse_int_like(obj.get("ringup_ns", 0))

    readout_duration_s = _ns_to_seconds(readout_ns)

    ringup_fraction = 0.0
    if readout_ns > 0:
        ringup_fraction = float(ringup_ns) / float(readout_ns)

    return {
        "n_readout": int(n_readout),
        "readout_duration_s": readout_duration_s,
        "ringup_fraction": ringup_fraction,
    }


def handle_cmd(obj: Dict[str, Any], fpga: VirtualFPGA, sim: QubitSim) -> Dict[str, Any]:
    """
    Commands:

      PING
        {"cmd":"PING"}

      RESET
        {"cmd":"RESET"}

      PLAY
        {"cmd":"PLAY","cfg":"0x1","amp_q8_8":"0080","phase_q8_8":"0100",
         "duration_ns":"000000C8","sigma_ns":"0000001E","pad_ns":"000000C8",
         "detune_hz":"00000000","envelope":"GAUSS"}

      MEASURE
        {"cmd":"MEASURE","cfg":"0x0","n_readout":"0040",
         "readout_ns":"00000400","ringup_ns":"00000200"}

    Notes:
      - cfg is currently accepted but ignored.
      - Hex strings with or without 0x are accepted.
      - Accidental spaces such as "0x 1" are tolerated.
    """
    cmd = str(obj.get("cmd", "")).upper()

    if cmd == "PING":
        return {"ok": True, "msg": "PONG"}

    if cmd == "RESET":
        sim.reset()
        return {"ok": True, "msg": "RESET_DONE"}

    if cmd == "PLAY":
        dec = _decode_play(obj)

        t, env, Iw, Qw = fpga.render_iq(dec["pulse"], pad_s=dec["pad_s"])

        u = iq_to_complex_envelope(t, Iw, Qw, if_hz=float(fpga.if_hz))
        p1 = sim.pulse_p1_from_envelope(
            t,
            u,
            detuning_hz=dec["detuning_hz"],
        )

        return {"ok": True, "msg": "PLAY_DONE", "p1_est": float(p1)}

    if cmd == "MEASURE":
        dec = _decode_measure(obj)

        t_ro, I_ro, Q_ro = sim.readout_waveform(
            n_readout=dec["n_readout"],
            readout_duration_s=dec["readout_duration_s"],
            ringup_fraction=dec["ringup_fraction"],
        )

        return {
            "ok": True,
            "n": int(len(t_ro)),
            "I": [float(x) for x in I_ro],
            "Q": [float(x) for x in Q_ro],
        }

    return {"ok": False, "err": f"Unknown cmd {cmd!r}"}


def _clip_i16(x: int) -> int:
    if x > 32767:
        return 32767
    if x < -32768:
        return -32768
    return x


def _float_to_q2_14_i16(value: float) -> tuple[int, bool]:
    """
    Convert one float sample to signed Q2.14 int16 with saturation.

    Returns:
      (quantized_value, clipped_flag)
    """
    scaled = int(round(float(value) * float(Q2_14Scale)))
    clipped = scaled > 32767 or scaled < -32768
    return _clip_i16(scaled), clipped


def float_iq_to_interleaved_q2_14_bytes(I_vals, Q_vals) -> tuple[bytes, Dict[str, Any]]:
    """
    Convert float I/Q arrays to interleaved little-endian signed Q2.14 int16 bytes:
      I0, Q0, I1, Q1, ...

    Example output layout for one sample pair:
      I0_lo I0_hi Q0_lo Q0_hi

    Returns:
      (payload_bytes, clip_info)
    """
    if len(I_vals) != len(Q_vals):
        raise ValueError("I and Q arrays must have the same length")

    packed = bytearray()

    i_clip_count = 0
    q_clip_count = 0
    first_i_clip_idx = None
    first_q_clip_idx = None
    first_i_clip_val = None
    first_q_clip_val = None

    for idx, (i_f, q_f) in enumerate(zip(I_vals, Q_vals)):
        i_i16, i_clipped = _float_to_q2_14_i16(float(i_f))
        q_i16, q_clipped = _float_to_q2_14_i16(float(q_f))

        if i_clipped:
            i_clip_count += 1
            if first_i_clip_idx is None:
                first_i_clip_idx = idx
                first_i_clip_val = float(i_f)

        if q_clipped:
            q_clip_count += 1
            if first_q_clip_idx is None:
                first_q_clip_idx = idx
                first_q_clip_val = float(q_f)

        packed += struct.pack("<hh", i_i16, q_i16)

    clip_info = {
        "any_clipped": (i_clip_count > 0 or q_clip_count > 0),
        "i_clip_count": i_clip_count,
        "q_clip_count": q_clip_count,
        "first_i_clip_idx": first_i_clip_idx,
        "first_q_clip_idx": first_q_clip_idx,
        "first_i_clip_val": first_i_clip_val,
        "first_q_clip_val": first_q_clip_val,
        "q_format": "Q2.14",
        "q_min_float": Q2_14MinFloat,
        "q_max_float": Q2_14MaxFloat,
    }

    return bytes(packed), clip_info


def build_waveform_packet(I_vals, Q_vals) -> tuple[bytes, Dict[str, Any]]:
    """
    Build a binary packet:
      [0xA5][0x5A][0x02][N][interleaved signed Q2.14 IQ bytes]

    N is the number of IQ pairs and must fit in one byte.

    Returns:
      (packet_bytes, clip_info)
    """
    n = len(I_vals)
    if len(Q_vals) != n:
        raise ValueError("I and Q arrays must have the same length")
    if n > 255:
        raise ValueError("n_readout must be <= 255 for 1-byte sample count")

    payload, clip_info = float_iq_to_interleaved_q2_14_bytes(I_vals, Q_vals)
    header = bytes([0xA5, 0x5A, 0x02, n])
    return header + payload, clip_info


def _format_clip_warning(clip_info: Dict[str, Any], n_samples: int) -> str:
    parts = [
        "WARNING Q2.14_CLIP",
        f'n={n_samples}',
        f'i_clip_count={clip_info["i_clip_count"]}',
        f'q_clip_count={clip_info["q_clip_count"]}',
        f'range=[{clip_info["q_min_float"]:.6f}, {clip_info["q_max_float"]:.6f}]',
    ]

    if clip_info["first_i_clip_idx"] is not None:
        parts.append(
            f'first_i_clip_idx={clip_info["first_i_clip_idx"]}'
        )
        parts.append(
            f'first_i_clip_val={clip_info["first_i_clip_val"]:.6f}'
        )

    if clip_info["first_q_clip_idx"] is not None:
        parts.append(
            f'first_q_clip_idx={clip_info["first_q_clip_idx"]}'
        )
        parts.append(
            f'first_q_clip_val={clip_info["first_q_clip_val"]:.6f}'
        )

    return " ".join(parts)


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

                # Binary packet to FPGA, with signed Q2.14 payload
                tx_packet, clip_info = build_waveform_packet(resp["I"], resp["Q"])

                if clip_info["any_clipped"]:
                    clip_msg = _format_clip_warning(clip_info, int(resp["n"]))

                    if debug:
                        _debug_log(
                            clip_msg,
                            debug=True,
                            log_path=None,
                        )

                    if log_path is not None:
                        _debug_log(
                            clip_msg,
                            debug=False,
                            log_path=log_path,
                        )

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
                        f"TX_BIN bytes={len(tx_packet)} sync=A5 5A type=02 n={resp['n']} fmt=Q2.14",
                        debug=True,
                        log_path=None,
                    )

                if log_path is not None:
                    _debug_log(
                        f"TX_BIN bytes={len(tx_packet)} sync=A5 5A type=02 n={resp['n']} fmt=Q2.14",
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
    