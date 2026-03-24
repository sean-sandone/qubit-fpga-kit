##------------------------------------------------------------------------------
## PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
##------------------------------------------------------------------------------
## Copyright (C) 2026 Sean Sandone
## SPDX-License-Identifier: AGPL-3.0-or-later
## Please see the LICENSE file for details.
## WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
##------------------------------------------------------------------------------

from __future__ import annotations

import struct
import sys
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional


PlayCfgDepth = 8
MeasureCfgDepth = 4
InstrDepth = 32

RegWrSync0 = 0xC3
RegWrSync1 = 0x3C

RegWrTypeControl = 0x10
RegWrTypeResetWait = 0x11
RegWrTypePlayCfg = 0x12
RegWrTypeMeasureCfg = 0x13
RegWrTypeInstr = 0x14

RegWrControlBitStartExp = 0
RegWrControlBitSoftReset = 1
RegWrControlBitReadAll = 2

RegDumpSync0 = 0xD4
RegDumpSync1 = 0x4D
RegDumpType = 0x20

RegDumpGroupScalar = 0x00

RegDumpGroupPlayCfg0 = 0x10
RegDumpGroupPlayCfg1 = 0x11
RegDumpGroupPlayCfg2 = 0x12
RegDumpGroupPlayCfg3 = 0x13
RegDumpGroupPlayCfg4 = 0x14
RegDumpGroupPlayCfg5 = 0x15
RegDumpGroupPlayValid = 0x16

RegDumpGroupMeasCfg0 = 0x20
RegDumpGroupMeasCfg1 = 0x21
RegDumpGroupMeasCfg2 = 0x22
RegDumpGroupMeasValid = 0x23

RegDumpGroupInstr = 0x30
RegDumpGroupInstrValid = 0x31

RegDumpScalarCount = 21

DumpRecordLength = 8
ExpectedDumpRecordCount = (
    RegDumpScalarCount
    + (PlayCfgDepth * 7)
    + (MeasureCfgDepth * 4)
    + (InstrDepth * 2)
)

EnvelopeSquare = 0
EnvelopeGauss = 1


@dataclass
class PlayCfg:
    amp_q8_8: int = 0
    phase_q8_8: int = 0
    duration_ns: int = 0
    sigma_ns: int = 0
    pad_ns: int = 0
    detune_hz: int = 0
    envelope: str = "SQUARE"


@dataclass
class MeasureCfg:
    n_readout: int = 0
    readout_ns: int = 0
    ringup_ns: int = 0


@dataclass
class ShadowRegs:
    start_exp: int = 0
    soft_reset: int = 0
    reset_wait_cycles: int = 0

    seq_busy: int = 0
    seq_done_sticky: int = 0

    play_cfg_any_valid: int = 0
    measure_cfg_any_valid: int = 0
    instr_any_valid: int = 0

    cal_sample_count: int = 0
    cal_i_avg: int = 0
    cal_q_avg: int = 0
    cal_i0_ref: int = 0
    cal_q0_ref: int = 0
    cal_i1_ref: int = 0
    cal_q1_ref: int = 0
    cal_i_threshold: int = 0
    cal_state_polarity: int = 0
    cal_i0q0_valid: int = 0
    cal_i1q1_valid: int = 0
    cal_threshold_valid: int = 0
    meas_state: int = 0
    meas_state_valid: int = 0

    play_cfgs: List[PlayCfg] = field(default_factory=lambda: [PlayCfg() for _ in range(PlayCfgDepth)])
    play_cfg_valid: List[int] = field(default_factory=lambda: [0 for _ in range(PlayCfgDepth)])

    measure_cfgs: List[MeasureCfg] = field(default_factory=lambda: [MeasureCfg() for _ in range(MeasureCfgDepth)])
    measure_cfg_valid: List[int] = field(default_factory=lambda: [0 for _ in range(MeasureCfgDepth)])

    instr_words: List[int] = field(default_factory=lambda: [0 for _ in range(InstrDepth)])
    instr_valid: List[int] = field(default_factory=lambda: [0 for _ in range(InstrDepth)])

    last_dump_ok: bool = False
    last_dump_record_count: int = 0


def poll_console_key() -> str | None:
    """
    Cross-platform single-key polling.

    Returns:
      one-character string if a key is available, else None
    """
    try:
        import msvcrt  # type: ignore

        if msvcrt.kbhit():
            ch = msvcrt.getwch()
            if ch in ("\x00", "\xe0"):
                if msvcrt.kbhit():
                    _ = msvcrt.getwch()
                return None
            return ch
        return None
    except Exception:
        pass

    try:
        import select

        if select.select([sys.stdin], [], [], 0.0)[0]:
            line = sys.stdin.readline()
            if not line:
                return None
            return line[:1]
    except Exception:
        pass

    return None


class RegisterDumpDecoder:
    def __init__(self, owner: "UartMenu"):
        self.owner = owner
        self.reset()

    def reset(self) -> None:
        self._buf = bytearray()
        self._active = False
        self._records_seen = 0
        self._play_words: List[List[int]] = [[0 for _ in range(6)] for _ in range(PlayCfgDepth)]
        self._play_word_seen: List[List[bool]] = [[False for _ in range(6)] for _ in range(PlayCfgDepth)]
        self._play_valid: List[int] = [0 for _ in range(PlayCfgDepth)]

        self._measure_words: List[List[int]] = [[0 for _ in range(3)] for _ in range(MeasureCfgDepth)]
        self._measure_word_seen: List[List[bool]] = [[False for _ in range(3)] for _ in range(MeasureCfgDepth)]
        self._measure_valid: List[int] = [0 for _ in range(MeasureCfgDepth)]

        self._instr_words: List[int] = [0 for _ in range(InstrDepth)]
        self._instr_word_seen: List[bool] = [False for _ in range(InstrDepth)]
        self._instr_valid: List[int] = [0 for _ in range(InstrDepth)]

        self._new_shadow = ShadowRegs()

    def feed_record(self, record: bytes) -> Optional[ShadowRegs]:
        if len(record) != DumpRecordLength:
            return None
        if record[0] != RegDumpSync0 or record[1] != RegDumpSync1 or record[2] != RegDumpType:
            return None

        if not self._active:
            self.reset()
            self._active = True

        group = record[3]
        index = record[4]
        value = struct.unpack("<I", record[5:9])[0]

        self._records_seen += 1
        self._apply_record(group, index, value)

        if self._records_seen >= ExpectedDumpRecordCount:
            self._finalize_shadow()
            shadow = self._new_shadow
            shadow.last_dump_ok = True
            shadow.last_dump_record_count = self._records_seen
            self.reset()
            return shadow

        return None

    def _apply_record(self, group: int, index: int, value: int) -> None:
        if group == RegDumpGroupScalar:
            self._apply_scalar(index, value)
            return

        if group in (
            RegDumpGroupPlayCfg0,
            RegDumpGroupPlayCfg1,
            RegDumpGroupPlayCfg2,
            RegDumpGroupPlayCfg3,
            RegDumpGroupPlayCfg4,
            RegDumpGroupPlayCfg5,
        ):
            if 0 <= index < PlayCfgDepth:
                word_sel = group - RegDumpGroupPlayCfg0
                if 0 <= word_sel < 6:
                    self._play_words[index][word_sel] = value & 0xFFFFFFFF
                    self._play_word_seen[index][word_sel] = True
            return

        if group == RegDumpGroupPlayValid:
            if 0 <= index < PlayCfgDepth:
                self._play_valid[index] = 1 if (value & 0x1) else 0
            return

        if group in (RegDumpGroupMeasCfg0, RegDumpGroupMeasCfg1, RegDumpGroupMeasCfg2):
            if 0 <= index < MeasureCfgDepth:
                word_sel = group - RegDumpGroupMeasCfg0
                self._measure_words[index][word_sel] = value & 0xFFFFFFFF
                self._measure_word_seen[index][word_sel] = True
            return

        if group == RegDumpGroupMeasValid:
            if 0 <= index < MeasureCfgDepth:
                self._measure_valid[index] = 1 if (value & 0x1) else 0
            return

        if group == RegDumpGroupInstr:
            if 0 <= index < InstrDepth:
                self._instr_words[index] = value & 0xFFFFFFFF
                self._instr_word_seen[index] = True
            return

        if group == RegDumpGroupInstrValid:
            if 0 <= index < InstrDepth:
                self._instr_valid[index] = 1 if (value & 0x1) else 0
            return

    def _apply_scalar(self, index: int, value: int) -> None:
        if index == 0:
            self._new_shadow.reset_wait_cycles = value & 0xFFFFFFFF
        elif index == 1:
            self._new_shadow.start_exp = 1 if (value & 0x1) else 0
        elif index == 2:
            self._new_shadow.soft_reset = 1 if (value & 0x1) else 0
        elif index == 3:
            self._new_shadow.seq_busy = 1 if (value & 0x1) else 0
        elif index == 4:
            self._new_shadow.seq_done_sticky = 1 if (value & 0x1) else 0
        elif index == 5:
            self._new_shadow.play_cfg_any_valid = 1 if (value & 0x1) else 0
        elif index == 6:
            self._new_shadow.measure_cfg_any_valid = 1 if (value & 0x1) else 0
        elif index == 7:
            self._new_shadow.instr_any_valid = 1 if (value & 0x1) else 0
        elif index == 8:
            self._new_shadow.cal_sample_count = value & 0xFFFF
        elif index == 9:
            self._new_shadow.cal_i_avg = self._u16_signed(value)
        elif index == 10:
            self._new_shadow.cal_q_avg = self._u16_signed(value)
        elif index == 11:
            self._new_shadow.cal_i0_ref = self._u16_signed(value)
        elif index == 12:
            self._new_shadow.cal_q0_ref = self._u16_signed(value)
        elif index == 13:
            self._new_shadow.cal_i1_ref = self._u16_signed(value)
        elif index == 14:
            self._new_shadow.cal_q1_ref = self._u16_signed(value)
        elif index == 15:
            self._new_shadow.cal_i_threshold = self._u16_signed(value)
        elif index == 16:
            self._new_shadow.cal_state_polarity = 1 if (value & 0x1) else 0
        elif index == 17:
            self._new_shadow.cal_i0q0_valid = 1 if (value & 0x1) else 0
        elif index == 18:
            self._new_shadow.cal_i1q1_valid = 1 if (value & 0x1) else 0
        elif index == 19:
            self._new_shadow.cal_threshold_valid = 1 if (value & 0x1) else 0
        elif index == 20:
            self._new_shadow.meas_state = 1 if (value & 0x1) else 0
            self._new_shadow.meas_state_valid = 1 if (value & 0x2) else 0

    def _finalize_shadow(self) -> None:
        for idx in range(PlayCfgDepth):
            self._new_shadow.play_cfg_valid[idx] = self._play_valid[idx]
            if all(self._play_word_seen[idx]):
                self._new_shadow.play_cfgs[idx] = self._decode_play_cfg_words(self._play_words[idx])

        for idx in range(MeasureCfgDepth):
            self._new_shadow.measure_cfg_valid[idx] = self._measure_valid[idx]
            if all(self._measure_word_seen[idx]):
                self._new_shadow.measure_cfgs[idx] = self._decode_measure_cfg_words(self._measure_words[idx])

        for idx in range(InstrDepth):
            self._new_shadow.instr_valid[idx] = self._instr_valid[idx]
            if self._instr_word_seen[idx]:
                self._new_shadow.instr_words[idx] = self._instr_words[idx]

    @staticmethod
    def _u16_signed(value: int) -> int:
        value &= 0xFFFF
        return value - 0x10000 if (value & 0x8000) else value

    @staticmethod
    def _u32_signed(value: int) -> int:
        value &= 0xFFFFFFFF
        return value - 0x100000000 if (value & 0x80000000) else value

    @staticmethod
    def _bit_slice(flat: int, msb: int, lsb: int) -> int:
        width = msb - lsb + 1
        return (flat >> lsb) & ((1 << width) - 1)

    def _decode_play_cfg_words(self, words: List[int]) -> PlayCfg:
        flat = 0
        for word_sel, word in enumerate(words):
            flat |= (int(word) & 0xFFFFFFFF) << (32 * word_sel)

        amp_q8_8 = self._bit_slice(flat, 163, 148)
        phase_q8_8 = self._bit_slice(flat, 147, 132)
        duration_ns = self._bit_slice(flat, 131, 100)
        sigma_ns = self._bit_slice(flat, 99, 68)
        pad_ns = self._bit_slice(flat, 67, 36)
        detune_hz = self._u32_signed(self._bit_slice(flat, 35, 4))
        envelope = self._bit_slice(flat, 3, 0)

        return PlayCfg(
            amp_q8_8=amp_q8_8,
            phase_q8_8=phase_q8_8,
            duration_ns=duration_ns,
            sigma_ns=sigma_ns,
            pad_ns=pad_ns,
            detune_hz=detune_hz,
            envelope="GAUSS" if envelope == EnvelopeGauss else "SQUARE",
        )

    def _decode_measure_cfg_words(self, words: List[int]) -> MeasureCfg:
        flat = 0
        for word_sel, word in enumerate(words):
            flat |= (int(word) & 0xFFFFFFFF) << (32 * word_sel)

        n_readout = self._bit_slice(flat, 79, 64)
        readout_ns = self._bit_slice(flat, 63, 32)
        ringup_ns = self._bit_slice(flat, 31, 0)

        return MeasureCfg(
            n_readout=n_readout,
            readout_ns=readout_ns,
            ringup_ns=ringup_ns,
        )


class UartMenu:
    def __init__(self, send_packet_cb: Callable[[str, bytes], None]):
        self._send_packet_cb = send_packet_cb
        self.shadow = ShadowRegs()
        self.dump_decoder = RegisterDumpDecoder(self)
        self._dump_complete_cb: Optional[Callable[[ShadowRegs], None]] = None

    def set_dump_complete_callback(self, cb: Callable[[ShadowRegs], None]) -> None:
        self._dump_complete_cb = cb

    # -------------------------------------------------------------------------
    # Packet builders
    # -------------------------------------------------------------------------

    @staticmethod
    def _header(pkt_type: int) -> bytearray:
        return bytearray([RegWrSync0, RegWrSync1, pkt_type])

    @staticmethod
    def _envelope_to_int(envelope: str) -> int:
        env = str(envelope).strip().upper()
        return EnvelopeGauss if env == "GAUSS" else EnvelopeSquare

    def build_control_packet(self, start_exp: int, soft_reset: int, read_all: int = 0) -> bytes:
        flags = (
            ((1 if start_exp else 0) << RegWrControlBitStartExp)
            | ((1 if soft_reset else 0) << RegWrControlBitSoftReset)
            | ((1 if read_all else 0) << RegWrControlBitReadAll)
        )
        pkt = self._header(RegWrTypeControl)
        pkt.append(flags & 0xFF)
        return bytes(pkt)

    def build_read_all_packet(self) -> bytes:
        return self.build_control_packet(0, 0, 1)

    def build_reset_wait_packet(self, cycles: int) -> bytes:
        pkt = self._header(RegWrTypeResetWait)
        pkt += struct.pack("<I", int(cycles) & 0xFFFFFFFF)
        return bytes(pkt)

    def build_play_cfg_packet(self, index: int, cfg: PlayCfg) -> bytes:
        pkt = self._header(RegWrTypePlayCfg)
        pkt.append(int(index) & 0xFF)
        pkt += struct.pack(
            "<HHIIIIB",
            int(cfg.amp_q8_8) & 0xFFFF,
            int(cfg.phase_q8_8) & 0xFFFF,
            int(cfg.duration_ns) & 0xFFFFFFFF,
            int(cfg.sigma_ns) & 0xFFFFFFFF,
            int(cfg.pad_ns) & 0xFFFFFFFF,
            int(cfg.detune_hz) & 0xFFFFFFFF,
            self._envelope_to_int(cfg.envelope) & 0xFF,
        )
        return bytes(pkt)

    def build_measure_cfg_packet(self, index: int, cfg: MeasureCfg) -> bytes:
        pkt = self._header(RegWrTypeMeasureCfg)
        pkt.append(int(index) & 0xFF)
        pkt += struct.pack(
            "<HII",
            int(cfg.n_readout) & 0xFFFF,
            int(cfg.readout_ns) & 0xFFFFFFFF,
            int(cfg.ringup_ns) & 0xFFFFFFFF,
        )
        return bytes(pkt)

    def build_instr_packet(self, index: int, instr_word: int) -> bytes:
        pkt = self._header(RegWrTypeInstr)
        pkt.append(int(index) & 0xFF)
        pkt += struct.pack("<I", int(instr_word) & 0xFFFFFFFF)
        return bytes(pkt)

    # -------------------------------------------------------------------------
    # Send helpers
    # -------------------------------------------------------------------------

    def _send_packet(self, label: str, pkt: bytes) -> None:
        self._send_packet_cb(label, pkt)

    def _send_and_confirm(self, label: str, pkt: bytes) -> None:
        self._send_packet(label, pkt)
        self.request_register_dump()

    def request_register_dump(self) -> None:
        self._send_packet("CONTROL_READ_ALL", self.build_read_all_packet())

    def send_control(self) -> None:
        pkt = self.build_control_packet(self.shadow.start_exp, self.shadow.soft_reset, 0)
        self._send_and_confirm("CONTROL", pkt)

    def send_reset_wait(self) -> None:
        pkt = self.build_reset_wait_packet(self.shadow.reset_wait_cycles)
        self._send_and_confirm("RESET_WAIT", pkt)

    def send_play_cfg(self, index: int) -> None:
        pkt = self.build_play_cfg_packet(index, self.shadow.play_cfgs[index])
        self._send_and_confirm(f"PLAY_CFG[{index}]", pkt)

    def send_measure_cfg(self, index: int) -> None:
        pkt = self.build_measure_cfg_packet(index, self.shadow.measure_cfgs[index])
        self._send_and_confirm(f"MEASURE_CFG[{index}]", pkt)

    def send_instr(self, index: int) -> None:
        pkt = self.build_instr_packet(index, self.shadow.instr_words[index])
        self._send_and_confirm(f"INSTR[{index}]", pkt)

    def send_all_play_cfgs(self) -> None:
        for idx in range(PlayCfgDepth):
            self.send_play_cfg(idx)

    def send_all_measure_cfgs(self) -> None:
        for idx in range(MeasureCfgDepth):
            self.send_measure_cfg(idx)

    def send_all_instr(self) -> None:
        for idx in range(InstrDepth):
            self.send_instr(idx)

    def send_all_registers(self) -> None:
        self.send_control()
        self.send_reset_wait()
        self.send_all_play_cfgs()
        self.send_all_measure_cfgs()
        self.send_all_instr()

    def send_start_experiment_pulse(self) -> None:
        pkt = self.build_control_packet(1, self.shadow.soft_reset, 0)
        self._send_and_confirm("CONTROL_START_EXP", pkt)

    def send_soft_reset_pulse(self) -> None:
        pkt = self.build_control_packet(self.shadow.start_exp, 1, 0)
        self._send_and_confirm("CONTROL_SOFT_RESET", pkt)

    # -------------------------------------------------------------------------
    # Dump ingest
    # -------------------------------------------------------------------------

    def ingest_dump_record(self, record: bytes) -> Optional[ShadowRegs]:
        new_shadow = self.dump_decoder.feed_record(record)
        if new_shadow is None:
            return None
        self.shadow = new_shadow
        if self._dump_complete_cb is not None:
            self._dump_complete_cb(self.shadow)
        return self.shadow

    # -------------------------------------------------------------------------
    # Formatting helpers
    # -------------------------------------------------------------------------

    @staticmethod
    def _parse_int(text: str, current: int = 0) -> int:
        s = str(text).strip()
        if not s:
            return int(current)

        s = s.replace(" ", "").replace("_", "")
        if s.lower().startswith("0x"):
            return int(s, 16)
        if any(c in "abcdefABCDEF" for c in s):
            return int(s, 16)
        return int(s, 10)

    @staticmethod
    def _hex_u16(x: int) -> str:
        return f"0x{int(x) & 0xFFFF:04X}"

    @staticmethod
    def _hex_u32(x: int) -> str:
        return f"0x{int(x) & 0xFFFFFFFF:08X}"

    @staticmethod
    def _input_with_default(prompt: str, default: str) -> str:
        entered = input(f"{prompt} [{default}]: ").strip()
        return entered if entered else default

    @staticmethod
    def _pause() -> None:
        input("\nPress Enter to continue...")

    def _print_packet_formats(self) -> None:
        print()
        print("CONTROL      : C3 3C 10 [flags bit0=start_exp bit1=soft_reset bit2=read_all]")
        print("RESET_WAIT   : C3 3C 11 [u32 little-endian]")
        print("PLAY_CFG     : C3 3C 12 [addr][amp u16][phase u16][duration u32][sigma u32][pad u32][detune u32][envelope u8]")
        print("MEASURE_CFG  : C3 3C 13 [addr][n_readout u16][readout_ns u32][ringup_ns u32]")
        print("INSTR        : C3 3C 14 [addr][instr_word u32 little-endian]")
        print("READ_ALL TX  : C3 3C 10 [flags with bit2=1]")
        print("DUMP RX      : D4 4D 20 [group][index][u32 little-endian]")

    def _print_summary(self) -> None:
        print()
        print("Control / status:")
        print(f"  start_exp           = {self.shadow.start_exp}")
        print(f"  soft_reset          = {self.shadow.soft_reset}")
        print(f"  reset_wait_cycles   = {self.shadow.reset_wait_cycles}")
        print(f"  seq_busy            = {self.shadow.seq_busy}")
        print(f"  seq_done_sticky     = {self.shadow.seq_done_sticky}")
        print(f"  play_cfg_any_valid  = {self.shadow.play_cfg_any_valid}")
        print(f"  measure_cfg_any_valid = {self.shadow.measure_cfg_any_valid}")
        print(f"  instr_any_valid     = {self.shadow.instr_any_valid}")
        print(f"  last_dump_ok        = {self.shadow.last_dump_ok}")
        print(f"  last_dump_records   = {self.shadow.last_dump_record_count}")
        print()
        print("PLAY CFG:")
        for idx, cfg in enumerate(self.shadow.play_cfgs):
            print(
                f"  [{idx}] "
                f"valid={self.shadow.play_cfg_valid[idx]} "
                f"amp={self._hex_u16(cfg.amp_q8_8)} "
                f"phase={self._hex_u16(cfg.phase_q8_8)} "
                f"duration={self._hex_u32(cfg.duration_ns)} "
                f"sigma={self._hex_u32(cfg.sigma_ns)} "
                f"pad={self._hex_u32(cfg.pad_ns)} "
                f"detune={self._hex_u32(cfg.detune_hz)} "
                f"env={cfg.envelope}"
            )
        print()
        print("MEASURE CFG:")
        for idx, cfg in enumerate(self.shadow.measure_cfgs):
            print(
                f"  [{idx}] "
                f"valid={self.shadow.measure_cfg_valid[idx]} "
                f"n_readout={self._hex_u16(cfg.n_readout)} "
                f"readout_ns={self._hex_u32(cfg.readout_ns)} "
                f"ringup_ns={self._hex_u32(cfg.ringup_ns)}"
            )
        print()
        print("INSTR:")
        for idx, word in enumerate(self.shadow.instr_words):
            print(f"  [{idx}] valid={self.shadow.instr_valid[idx]} {self._hex_u32(word)}")

    # -------------------------------------------------------------------------
    # Menu handlers
    # -------------------------------------------------------------------------

    def _menu_control(self) -> None:
        while True:
            print()
            print("Control register:")
            print("  1. Set start_exp = 1")
            print("  2. Set start_exp = 0")
            print("  3. Set soft_reset = 1")
            print("  4. Set soft_reset = 0")
            print("  5. Enter both bits manually")
            print("  6. Send current control value")
            print("  7. Request FPGA register dump")
            print("  b. Back")
            sel = input("Select: ").strip().lower()

            if sel == "1":
                self.shadow.start_exp = 1
                self.send_control()
            elif sel == "2":
                self.shadow.start_exp = 0
                self.send_control()
            elif sel == "3":
                self.shadow.soft_reset = 1
                self.send_control()
            elif sel == "4":
                self.shadow.soft_reset = 0
                self.send_control()
            elif sel == "5":
                self.shadow.start_exp = 1 if self._parse_int(input("start_exp (0/1): "), self.shadow.start_exp) != 0 else 0
                self.shadow.soft_reset = 1 if self._parse_int(input("soft_reset (0/1): "), self.shadow.soft_reset) != 0 else 0
                self.send_control()
            elif sel == "6":
                self.send_control()
            elif sel == "7":
                self.request_register_dump()
            elif sel == "b":
                return
            else:
                print("Unknown selection")

    def _menu_reset_wait(self) -> None:
        print()
        val = self._input_with_default("Enter reset_wait_cycles", str(self.shadow.reset_wait_cycles))
        self.shadow.reset_wait_cycles = self._parse_int(val, self.shadow.reset_wait_cycles)
        self.send_reset_wait()

    def _menu_play_cfg(self) -> None:
        idx_text = self._input_with_default(f"PLAY CFG index [0..{PlayCfgDepth - 1}]", "0")
        idx = self._parse_int(idx_text, 0)
        if idx < 0 or idx >= PlayCfgDepth:
            print("Invalid index")
            return

        cfg = self.shadow.play_cfgs[idx]

        while True:
            print()
            print(f"PLAY CFG[{idx}] valid={self.shadow.play_cfg_valid[idx]}:")
            print("  1. Edit all fields")
            print("  2. Edit amp only")
            print("  3. Edit phase only")
            print("  4. Edit duration only")
            print("  5. Edit sigma only")
            print("  6. Edit pad only")
            print("  7. Edit detune only")
            print("  8. Edit envelope only")
            print("  9. Send current local value for this index")
            print("  b. Back")
            sel = input("Select: ").strip().lower()

            try:
                if sel == "1":
                    cfg.amp_q8_8 = self._parse_int(self._input_with_default("amp_q8_8", self._hex_u16(cfg.amp_q8_8)), cfg.amp_q8_8)
                    cfg.phase_q8_8 = self._parse_int(self._input_with_default("phase_q8_8", self._hex_u16(cfg.phase_q8_8)), cfg.phase_q8_8)
                    cfg.duration_ns = self._parse_int(self._input_with_default("duration_ns", self._hex_u32(cfg.duration_ns)), cfg.duration_ns)
                    cfg.sigma_ns = self._parse_int(self._input_with_default("sigma_ns", self._hex_u32(cfg.sigma_ns)), cfg.sigma_ns)
                    cfg.pad_ns = self._parse_int(self._input_with_default("pad_ns", self._hex_u32(cfg.pad_ns)), cfg.pad_ns)
                    cfg.detune_hz = self._parse_int(self._input_with_default("detune_hz", self._hex_u32(cfg.detune_hz)), cfg.detune_hz)
                    cfg.envelope = self._input_with_default("envelope (SQUARE/GAUSS)", cfg.envelope).strip().upper()
                    self.send_play_cfg(idx)
                elif sel == "2":
                    cfg.amp_q8_8 = self._parse_int(self._input_with_default("amp_q8_8", self._hex_u16(cfg.amp_q8_8)), cfg.amp_q8_8)
                    self.send_play_cfg(idx)
                elif sel == "3":
                    cfg.phase_q8_8 = self._parse_int(self._input_with_default("phase_q8_8", self._hex_u16(cfg.phase_q8_8)), cfg.phase_q8_8)
                    self.send_play_cfg(idx)
                elif sel == "4":
                    cfg.duration_ns = self._parse_int(self._input_with_default("duration_ns", self._hex_u32(cfg.duration_ns)), cfg.duration_ns)
                    self.send_play_cfg(idx)
                elif sel == "5":
                    cfg.sigma_ns = self._parse_int(self._input_with_default("sigma_ns", self._hex_u32(cfg.sigma_ns)), cfg.sigma_ns)
                    self.send_play_cfg(idx)
                elif sel == "6":
                    cfg.pad_ns = self._parse_int(self._input_with_default("pad_ns", self._hex_u32(cfg.pad_ns)), cfg.pad_ns)
                    self.send_play_cfg(idx)
                elif sel == "7":
                    cfg.detune_hz = self._parse_int(self._input_with_default("detune_hz", self._hex_u32(cfg.detune_hz)), cfg.detune_hz)
                    self.send_play_cfg(idx)
                elif sel == "8":
                    cfg.envelope = self._input_with_default("envelope (SQUARE/GAUSS)", cfg.envelope).strip().upper()
                    self.send_play_cfg(idx)
                elif sel == "9":
                    self.send_play_cfg(idx)
                elif sel == "b":
                    return
                else:
                    print("Unknown selection")
            except Exception as exc:
                print(f"Error: {exc}")

    def _menu_measure_cfg(self) -> None:
        idx_text = self._input_with_default(f"MEASURE CFG index [0..{MeasureCfgDepth - 1}]", "0")
        idx = self._parse_int(idx_text, 0)
        if idx < 0 or idx >= MeasureCfgDepth:
            print("Invalid index")
            return

        cfg = self.shadow.measure_cfgs[idx]

        while True:
            print()
            print(f"MEASURE CFG[{idx}] valid={self.shadow.measure_cfg_valid[idx]}:")
            print("  1. Edit all fields")
            print("  2. Edit n_readout only")
            print("  3. Edit readout_ns only")
            print("  4. Edit ringup_ns only")
            print("  5. Send current local value for this index")
            print("  b. Back")
            sel = input("Select: ").strip().lower()

            try:
                if sel == "1":
                    cfg.n_readout = self._parse_int(self._input_with_default("n_readout", self._hex_u16(cfg.n_readout)), cfg.n_readout)
                    cfg.readout_ns = self._parse_int(self._input_with_default("readout_ns", self._hex_u32(cfg.readout_ns)), cfg.readout_ns)
                    cfg.ringup_ns = self._parse_int(self._input_with_default("ringup_ns", self._hex_u32(cfg.ringup_ns)), cfg.ringup_ns)
                    self.send_measure_cfg(idx)
                elif sel == "2":
                    cfg.n_readout = self._parse_int(self._input_with_default("n_readout", self._hex_u16(cfg.n_readout)), cfg.n_readout)
                    self.send_measure_cfg(idx)
                elif sel == "3":
                    cfg.readout_ns = self._parse_int(self._input_with_default("readout_ns", self._hex_u32(cfg.readout_ns)), cfg.readout_ns)
                    self.send_measure_cfg(idx)
                elif sel == "4":
                    cfg.ringup_ns = self._parse_int(self._input_with_default("ringup_ns", self._hex_u32(cfg.ringup_ns)), cfg.ringup_ns)
                    self.send_measure_cfg(idx)
                elif sel == "5":
                    self.send_measure_cfg(idx)
                elif sel == "b":
                    return
                else:
                    print("Unknown selection")
            except Exception as exc:
                print(f"Error: {exc}")

    def _menu_instr(self) -> None:
        idx_text = self._input_with_default(f"Instruction index [0..{InstrDepth - 1}]", "0")
        idx = self._parse_int(idx_text, 0)
        if idx < 0 or idx >= InstrDepth:
            print("Invalid index")
            return

        while True:
            print()
            print(f"INSTR[{idx}] valid={self.shadow.instr_valid[idx]} value={self._hex_u32(self.shadow.instr_words[idx])}")
            print("  1. Enter raw 32-bit instruction word")
            print("  2. Build instruction from fields")
            print("  3. Send current local value for this index")
            print("  b. Back")
            sel = input("Select: ").strip().lower()

            try:
                if sel == "1":
                    self.shadow.instr_words[idx] = self._parse_int(
                        self._input_with_default("instr_word", self._hex_u32(self.shadow.instr_words[idx])),
                        self.shadow.instr_words[idx],
                    )
                    self.send_instr(idx)
                elif sel == "2":
                    opcode = self._parse_int(input("opcode (0..15): "), 0) & 0xF
                    flags = self._parse_int(input("flags (0..15): "), 0) & 0xF
                    cfg_index = self._parse_int(input("cfg_index (0..15): "), 0) & 0xF
                    operand = self._parse_int(input("operand (0..0xFFFFF): "), 0) & 0xFFFFF
                    word = (opcode << 28) | (flags << 24) | (cfg_index << 20) | operand
                    self.shadow.instr_words[idx] = word
                    print(f"Encoded word = {self._hex_u32(word)}")
                    self.send_instr(idx)
                elif sel == "3":
                    self.send_instr(idx)
                elif sel == "b":
                    return
                else:
                    print("Unknown selection")
            except Exception as exc:
                print(f"Error: {exc}")

    def _menu_batch(self) -> None:
        while True:
            print()
            print("Batch write:")
            print("  1. Send control only")
            print("  2. Send reset-wait only")
            print("  3. Send all PLAY configs")
            print("  4. Send all MEASURE configs")
            print("  5. Send all INSTR entries")
            print("  6. Send everything")
            print("  7. Request FPGA register dump")
            print("  b. Back")
            sel = input("Select: ").strip().lower()

            if sel == "1":
                self.send_control()
            elif sel == "2":
                self.send_reset_wait()
            elif sel == "3":
                self.send_all_play_cfgs()
            elif sel == "4":
                self.send_all_measure_cfgs()
            elif sel == "5":
                self.send_all_instr()
            elif sel == "6":
                self.send_all_registers()
            elif sel == "7":
                self.request_register_dump()
            elif sel == "b":
                return
            else:
                print("Unknown selection")

    def run(self) -> None:
        while True:
            print()
            print("================ UART SERVER MENU ================")
            print("1. Show register summary")
            print("2. Write control register")
            print("3. Write reset-wait register")
            print("4. Write PLAY config")
            print("5. Write MEASURE config")
            print("6. Write instruction memory")
            print("7. Show current local shadow registers")
            print("8. Request register dump from FPGA")
            print("9. Send batch: write all registers")
            print("10. Start experiment")
            print("11. Soft reset control bit")
            print("12. Help: packet formats")
            print("q. Exit menu")
            print("==================================================")
            sel = input("Select: ").strip().lower()

            if sel == "1":
                self._print_summary()
                self._pause()
            elif sel == "2":
                self._menu_control()
            elif sel == "3":
                self._menu_reset_wait()
            elif sel == "4":
                self._menu_play_cfg()
            elif sel == "5":
                self._menu_measure_cfg()
            elif sel == "6":
                self._menu_instr()
            elif sel == "7":
                self._print_summary()
                self._pause()
            elif sel == "8":
                self.request_register_dump()
            elif sel == "9":
                self._menu_batch()
            elif sel == "10":
                self.send_start_experiment_pulse()
            elif sel == "11":
                self.send_soft_reset_pulse()
            elif sel == "12":
                self._print_packet_formats()
                self._pause()
            elif sel == "q":
                return
            else:
                print("Unknown selection")
