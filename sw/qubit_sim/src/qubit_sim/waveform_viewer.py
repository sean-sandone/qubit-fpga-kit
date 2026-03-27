##------------------------------------------------------------------------------
## PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
##------------------------------------------------------------------------------
## Copyright (C) 2026 Sean Sandone
## SPDX-License-Identifier: AGPL-3.0-or-later
## Please see the LICENSE file for details.
## WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
##------------------------------------------------------------------------------

from __future__ import annotations

import base64
import io
import struct
import threading
from dataclasses import dataclass
from typing import Any, Dict, List, Tuple

import matplotlib
matplotlib.use('Agg')
from matplotlib.figure import Figure

from .uart_menu import (
    EnvelopeGauss,
    InstrDepth,
    MeasureCfg,
    MeasureCfgDepth,
    PlayCfg,
    PlayCfgDepth,
    RegWrSync0,
    RegWrSync1,
    RegWrTypeControl,
    RegWrTypeInstr,
    RegWrTypeMeasureCfg,
    RegWrTypePlayCfg,
    RegWrTypeResetWait,
    ShadowRegs,
    UartMenu,
)
from .virtual_fpga import VirtualFPGA


OpcodeNames = {
    0x0: 'NOP',
    0x1: 'PLAY',
    0x2: 'MEASURE',
    0x3: 'WAIT',
    0x4: 'END',
    0x5: 'JUMP',
    0x6: 'WAIT_RESET',
    0x7: 'ACCUM_CLEAR',
    0x8: 'ACCUM',
    0x9: 'ACCUM_AVG',
    0xA: 'LOOP',
}

@dataclass
class PreviewImages:
    env_thumb_data_url: str
    iq_thumb_data_url: str
    env_large_data_url: str
    iq_large_data_url: str


@dataclass
class ExperimentPlotImages:
    i_avg_data_url: str
    q_avg_data_url: str
    meas_state_data_url: str


class PacketMirror:
    def __init__(self) -> None:
        self.shadow = ShadowRegs()
        self.packet_log: List[Tuple[str, bytes]] = []

    def apply_packet(self, label: str, packet: bytes) -> None:
        if len(packet) < 3:
            raise ValueError('packet too short')
        if packet[0] != RegWrSync0 or packet[1] != RegWrSync1:
            raise ValueError('bad sync bytes')

        pkt_type = packet[2]
        self.packet_log.append((label, bytes(packet)))

        if pkt_type == RegWrTypeControl:
            if len(packet) != 4:
                raise ValueError('control packet length mismatch')
            flags = packet[3]
            self.shadow.start_exp = 1 if (flags & 0x01) else 0
            self.shadow.soft_reset = 1 if (flags & 0x02) else 0
            return

        if pkt_type == RegWrTypeResetWait:
            if len(packet) != 7:
                raise ValueError('reset wait packet length mismatch')
            (cycles,) = struct.unpack('<I', packet[3:7])
            self.shadow.reset_wait_cycles = cycles
            return

        if pkt_type == RegWrTypePlayCfg:
            if len(packet) != 25:
                raise ValueError('play cfg packet length mismatch')
            index = packet[3]
            if index >= PlayCfgDepth:
                raise ValueError(f'play cfg index out of range: {index}')
            amp_q8_8, phase_q8_8, duration_ns, sigma_ns, pad_ns, detune_hz_u32, envelope = struct.unpack(
                '<HHIIIIB', packet[4:25]
            )
            self.shadow.play_cfgs[index] = PlayCfg(
                amp_q8_8=amp_q8_8,
                phase_q8_8=phase_q8_8,
                duration_ns=duration_ns,
                sigma_ns=sigma_ns,
                pad_ns=pad_ns,
                detune_hz=self._u32_to_i32(detune_hz_u32),
                envelope='GAUSS' if envelope == EnvelopeGauss else 'SQUARE',
            )
            return

        if pkt_type == RegWrTypeMeasureCfg:
            if len(packet) != 14:
                raise ValueError('measure cfg packet length mismatch')
            index = packet[3]
            if index >= MeasureCfgDepth:
                raise ValueError(f'measure cfg index out of range: {index}')
            n_readout, readout_ns, ringup_ns = struct.unpack('<HII', packet[4:14])
            self.shadow.measure_cfgs[index] = MeasureCfg(
                n_readout=n_readout,
                readout_ns=readout_ns,
                ringup_ns=ringup_ns,
            )
            return

        if pkt_type == RegWrTypeInstr:
            if len(packet) != 8:
                raise ValueError('instr packet length mismatch')
            index = packet[3]
            if index >= InstrDepth:
                raise ValueError(f'instr index out of range: {index}')
            (word,) = struct.unpack('<I', packet[4:8])
            self.shadow.instr_words[index] = word
            return

        raise ValueError(f'unknown packet type: 0x{pkt_type:02X}')

    def replace_shadow(self, shadow: ShadowRegs) -> None:
        self.shadow = ShadowRegs(
            start_exp=int(shadow.start_exp),
            soft_reset=int(shadow.soft_reset),
            reset_wait_cycles=int(shadow.reset_wait_cycles),
            seq_busy=int(shadow.seq_busy),
            seq_done_sticky=int(shadow.seq_done_sticky),
            play_cfg_any_valid=int(shadow.play_cfg_any_valid),
            measure_cfg_any_valid=int(shadow.measure_cfg_any_valid),
            instr_any_valid=int(shadow.instr_any_valid),
            cal_sample_count=int(shadow.cal_sample_count),
            cal_i_avg=int(shadow.cal_i_avg),
            cal_q_avg=int(shadow.cal_q_avg),
            cal_i0_ref=int(shadow.cal_i0_ref),
            cal_q0_ref=int(shadow.cal_q0_ref),
            cal_i1_ref=int(shadow.cal_i1_ref),
            cal_q1_ref=int(shadow.cal_q1_ref),
            cal_i_threshold=int(shadow.cal_i_threshold),
            cal_state_polarity=int(shadow.cal_state_polarity),
            cal_i0q0_valid=int(shadow.cal_i0q0_valid),
            cal_i1q1_valid=int(shadow.cal_i1q1_valid),
            cal_threshold_valid=int(shadow.cal_threshold_valid),
            meas_state=int(shadow.meas_state),
            meas_state_valid=int(shadow.meas_state_valid),
            play_cfgs=[
                PlayCfg(
                    amp_q8_8=int(cfg.amp_q8_8),
                    phase_q8_8=int(cfg.phase_q8_8),
                    duration_ns=int(cfg.duration_ns),
                    sigma_ns=int(cfg.sigma_ns),
                    pad_ns=int(cfg.pad_ns),
                    detune_hz=int(cfg.detune_hz),
                    envelope=str(cfg.envelope),
                )
                for cfg in shadow.play_cfgs
            ],
            play_cfg_valid=[int(x) for x in shadow.play_cfg_valid],
            measure_cfgs=[
                MeasureCfg(
                    n_readout=int(cfg.n_readout),
                    readout_ns=int(cfg.readout_ns),
                    ringup_ns=int(cfg.ringup_ns),
                )
                for cfg in shadow.measure_cfgs
            ],
            measure_cfg_valid=[int(x) for x in shadow.measure_cfg_valid],
            instr_words=[int(x) for x in shadow.instr_words],
            instr_valid=[int(x) for x in shadow.instr_valid],
            last_dump_ok=bool(shadow.last_dump_ok),
            last_dump_record_count=int(shadow.last_dump_record_count),
        )

    @staticmethod
    def _u32_to_i32(value: int) -> int:
        value &= 0xFFFFFFFF
        if value & 0x80000000:
            return value - 0x100000000
        return value


class WaveformRenderer:
    def __init__(self, fs_hz: float = 1.0e9, if_hz: float = 50.0e6):
        self.fs_hz = float(fs_hz)
        self.if_hz = float(if_hz)

        # Use a higher sample rate for preview rendering so the carrier looks
        # smooth even when the runtime/sample transport rate is lower.
        self.preview_fs_hz = max(self.fs_hz, 40.0 * self.if_hz, 1.0e9)
        self.fpga = VirtualFPGA(fs_hz=self.preview_fs_hz, if_hz=self.if_hz)

    @staticmethod
    def q8_8_to_float(value: int) -> float:
        value &= 0xFFFF
        signed = value - 0x10000 if value & 0x8000 else value
        return signed / 256.0

    @staticmethod
    def phase_word_to_rad(value: int) -> float:
        return (2.0 * 3.141592653589793 * float(value & 0xFFFF)) / 65536.0

    def play_cfg_to_pulse(self, cfg: PlayCfg) -> Dict[str, float | str]:
        env = str(cfg.envelope).strip().lower()
        if env not in ('square', 'gauss'):
            env = 'gauss'
        return {
            'amp': self.q8_8_to_float(cfg.amp_q8_8),
            'phase': self.phase_word_to_rad(cfg.phase_q8_8),
            'duration': float(cfg.duration_ns) * 1.0e-9,
            'sigma': max(float(cfg.sigma_ns) * 1.0e-9, 1.0e-12),
            'envelope': env,
        }

    def render_cfg(self, cfg: PlayCfg):
        pulse = self.play_cfg_to_pulse(cfg)
        return self.fpga.render_iq(pulse, pad_s=float(cfg.pad_ns) * 1.0e-9)

    @staticmethod
    def _fig_to_data_url(fig: Figure) -> str:
        buf = io.BytesIO()
        fig.savefig(buf, format='png', dpi=110, bbox_inches='tight')
        fig.clf()
        png = base64.b64encode(buf.getvalue()).decode('ascii')
        return f'data:image/png;base64,{png}'

    def _build_env_figure(self, t_s, env, title: str, width_in: float, height_in: float) -> Figure:
        fig = Figure(figsize=(width_in, height_in), dpi=100)
        ax = fig.add_subplot(111)
        ax.plot(t_s * 1.0e9, env)
        ax.set_title(title)
        ax.set_xlabel('Time (ns)')
        ax.set_ylabel('Envelope')
        ax.grid(True)
        fig.tight_layout()
        return fig

    def _build_iq_figure(self, t_s, i_wave, q_wave, title: str, width_in: float, height_in: float) -> Figure:
        fig = Figure(figsize=(width_in, height_in), dpi=100)
        ax = fig.add_subplot(111)
        ax.plot(t_s * 1.0e9, i_wave, label='I')
        ax.plot(t_s * 1.0e9, q_wave, label='Q')
        ax.set_title(title)
        ax.set_xlabel('Time (ns)')
        ax.set_ylabel('Amplitude')
        ax.grid(True)
        ax.legend(loc='upper right', fontsize=8)
        fig.tight_layout()
        return fig

    def _build_experiment_series_figure(
        self,
        xs,
        ys,
        title: str,
        ylabel: str,
        width_in: float = 6.2,
        height_in: float = 2.4,
    ) -> Figure:
        fig = Figure(figsize=(width_in, height_in), dpi=100)
        ax = fig.add_subplot(111)
        ax.plot(xs, ys, marker='o')
        ax.set_title(title)
        ax.set_xlabel('Captured Result Index')
        ax.set_ylabel(ylabel)
        ax.grid(True)
        fig.tight_layout()
        return fig

    def render_preview_images(self, cfg: PlayCfg) -> PreviewImages:
        t_s, env, i_wave, q_wave = self.render_cfg(cfg)
        env_small = self._build_env_figure(t_s, env, 'Envelope', 3.0, 1.6)
        iq_small = self._build_iq_figure(t_s, i_wave, q_wave, 'I/Q', 3.0, 1.6)
        env_large = self._build_env_figure(t_s, env, 'Envelope Preview', 7.0, 2.8)
        iq_large = self._build_iq_figure(t_s, i_wave, q_wave, 'I/Q Preview', 7.0, 2.8)
        return PreviewImages(
            env_thumb_data_url=self._fig_to_data_url(env_small),
            iq_thumb_data_url=self._fig_to_data_url(iq_small),
            env_large_data_url=self._fig_to_data_url(env_large),
            iq_large_data_url=self._fig_to_data_url(iq_large),
        )

    def render_experiment_plots(self, results: List[Dict[str, Any]]) -> ExperimentPlotImages:
        xs = list(range(len(results)))
        i_vals = [float(row.get('I_avg', 0.0)) for row in results]
        q_vals = [float(row.get('Q_avg', 0.0)) for row in results]
        meas_state_vals = [int(row.get('meas_state', 0)) for row in results]

        i_fig = self._build_experiment_series_figure(xs, i_vals, 'I_avg vs Captured Result Index', 'I_avg')
        q_fig = self._build_experiment_series_figure(xs, q_vals, 'Q_avg vs Captured Result Index', 'Q_avg')
        meas_state_fig = self._build_experiment_series_figure(xs, meas_state_vals, 'meas_state vs Captured Result Index', 'meas_state')

        return ExperimentPlotImages(
            i_avg_data_url=self._fig_to_data_url(i_fig),
            q_avg_data_url=self._fig_to_data_url(q_fig),
            meas_state_data_url=self._fig_to_data_url(meas_state_fig),
        )


class WaveformViewerApp:
    """
    Backend-only state holder for the Flask UI.
    Keeps packet mirroring and waveform generation in this module.
    """

    def __init__(self, fs_hz: float = 1.0e9, if_hz: float = 50.0e6):
        self.mirror = PacketMirror()
        self.renderer = WaveformRenderer(fs_hz=fs_hz, if_hz=if_hz)
        self.preview_cache: Dict[int, PreviewImages] = {}
        self.experiment_results: List[Dict[str, Any]] = []
        self.experiment_plot_cache: ExperimentPlotImages | None = None
        self._lock = threading.RLock()
        self._menu: UartMenu | None = None
        self._empty_play_cfg = PlayCfg()

    def attach_menu(self, menu: UartMenu) -> None:
        with self._lock:
            self._menu = menu

    def load_from_shadow(self, menu: UartMenu) -> None:
        with self._lock:
            self.attach_menu(menu)
            self.preview_cache.clear()
            self.mirror.replace_shadow(menu.shadow)

    def post_packet(self, label: str, packet: bytes) -> None:
        with self._lock:
            self.mirror.apply_packet(label, bytes(packet))
            self.preview_cache.clear()

    def reload_from_menu_shadow(self) -> None:
        with self._lock:
            if self._menu is None:
                return
            self.load_from_shadow(self._menu)

    def request_register_dump(self) -> None:
        with self._lock:
            if self._menu is not None:
                self._menu.request_register_dump()

    def clear_experiment_results(self) -> None:
        with self._lock:
            self.experiment_results = []
            self.experiment_plot_cache = None

    def capture_measure_result(
        self,
        *,
        i_avg_q2_14: int,
        q_avg_q2_14: int,
        i_avg: float,
        q_avg: float,
        meas_state: int,
    ) -> None:
        with self._lock:
            self.experiment_results.append({
                'index': len(self.experiment_results),
                'I_avg_q2_14': int(i_avg_q2_14),
                'Q_avg_q2_14': int(q_avg_q2_14),
                'I_avg': float(i_avg),
                'Q_avg': float(q_avg),
                'meas_state': int(meas_state),
            })
            self.experiment_plot_cache = None

    def send_start_experiment(self) -> None:
        with self._lock:
            self.experiment_results = []
            self.experiment_plot_cache = None
            if self._menu is not None:
                self._menu.send_start_experiment_pulse()

    def send_soft_reset(self) -> None:
        with self._lock:
            if self._menu is not None:
                self._menu.send_soft_reset_pulse()

    def send_all_registers(self) -> None:
        with self._lock:
            if self._menu is not None:
                self._menu.send_all_registers()

    @staticmethod
    def decode_instr(word: int) -> Dict[str, int | str]:
        opcode = (word >> 28) & 0xF
        flags = (word >> 24) & 0xF
        cfg = (word >> 20) & 0xF
        operand = word & 0xFFFFF
        opcode_name = OpcodeNames.get(opcode, f'OP_{opcode}')
        return {
            'opcode': opcode,
            'opcode_name': opcode_name,
            'flags': flags,
            'cfg': cfg,
            'operand': operand,
        }

    def _is_play_cfg_programmed(self, idx: int, cfg: PlayCfg) -> bool:
        return int(self.mirror.shadow.play_cfg_valid[idx]) != 0

    def _play_cfg_summary(self, cfg: PlayCfg) -> Dict[str, Any]:
        amp = self.renderer.q8_8_to_float(cfg.amp_q8_8)
        phase_rad = self.renderer.phase_word_to_rad(cfg.phase_q8_8)
        return {
            'amp_q8_8': f'0x{cfg.amp_q8_8 & 0xFFFF:04X}',
            'amp_float': amp,
            'phase_q8_8': f'0x{cfg.phase_q8_8 & 0xFFFF:04X}',
            'phase_rad': phase_rad,
            'duration_ns': int(cfg.duration_ns),
            'sigma_ns': int(cfg.sigma_ns),
            'pad_ns': int(cfg.pad_ns),
            'detune_hz': int(cfg.detune_hz),
            'envelope': str(cfg.envelope),
        }

    def get_state_snapshot(self) -> Dict[str, Any]:
        with self._lock:
            play_cfgs = []
            for idx, cfg in enumerate(self.mirror.shadow.play_cfgs):
                is_programmed = self._is_play_cfg_programmed(idx, cfg)

                previews = None
                if is_programmed:
                    previews = self.preview_cache.get(idx)
                    if previews is None:
                        previews = self.renderer.render_preview_images(cfg)
                        self.preview_cache[idx] = previews

                play_cfgs.append({
                    'index': idx,
                    'is_programmed': is_programmed,
                    'summary': self._play_cfg_summary(cfg) if is_programmed else None,
                    'preview': None if previews is None else {
                        'env_thumb': previews.env_thumb_data_url,
                        'iq_thumb': previews.iq_thumb_data_url,
                        'env_large': previews.env_large_data_url,
                        'iq_large': previews.iq_large_data_url,
                    },
                })

            measure_cfgs = []
            for idx, cfg in enumerate(self.mirror.shadow.measure_cfgs):
                measure_cfgs.append({
                    'index': idx,
                    'valid': int(self.mirror.shadow.measure_cfg_valid[idx]),
                    'n_readout': int(cfg.n_readout),
                    'readout_ns': int(cfg.readout_ns),
                    'ringup_ns': int(cfg.ringup_ns),
                })

            instructions = []
            for idx, word in enumerate(self.mirror.shadow.instr_words):
                dec = self.decode_instr(word)
                instructions.append({
                    'index': idx,
                    'valid': int(self.mirror.shadow.instr_valid[idx]),
                    'word_hex': f'0x{word:08X}',
                    'opcode_name': dec['opcode_name'],
                    'flags': dec['flags'],
                    'cfg': dec['cfg'],
                    'operand': dec['operand'],
                })

            experiment_plots = None
            if self.experiment_results:
                if self.experiment_plot_cache is None:
                    self.experiment_plot_cache = self.renderer.render_experiment_plots(self.experiment_results)
                experiment_plots = {
                    'i_avg': self.experiment_plot_cache.i_avg_data_url,
                    'q_avg': self.experiment_plot_cache.q_avg_data_url,
                    'meas_state': self.experiment_plot_cache.meas_state_data_url,
                }

            return {
                'experiment_results': {
                    'count': len(self.experiment_results),
                    'rows': [dict(row) for row in self.experiment_results],
                    'plots': experiment_plots,
                },
                'control': {
                    'start_exp': int(self.mirror.shadow.start_exp),
                    'soft_reset': int(self.mirror.shadow.soft_reset),
                    'reset_wait_cycles': int(self.mirror.shadow.reset_wait_cycles),
                    'seq_busy': int(self.mirror.shadow.seq_busy),
                    'seq_done_sticky': int(self.mirror.shadow.seq_done_sticky),
                    'play_cfg_any_valid': int(self.mirror.shadow.play_cfg_any_valid),
                    'measure_cfg_any_valid': int(self.mirror.shadow.measure_cfg_any_valid),
                    'instr_any_valid': int(self.mirror.shadow.instr_any_valid),
                    'last_dump_ok': bool(self.mirror.shadow.last_dump_ok),
                    'last_dump_record_count': int(self.mirror.shadow.last_dump_record_count),
                    'captured_packets': len(self.mirror.packet_log),
                },
                'calibration': {
                    'cal_sample_count': int(self.mirror.shadow.cal_sample_count),
                    'cal_i_avg': int(self.mirror.shadow.cal_i_avg),
                    'cal_q_avg': int(self.mirror.shadow.cal_q_avg),
                    'cal_i0_ref': int(self.mirror.shadow.cal_i0_ref),
                    'cal_q0_ref': int(self.mirror.shadow.cal_q0_ref),
                    'cal_i1_ref': int(self.mirror.shadow.cal_i1_ref),
                    'cal_q1_ref': int(self.mirror.shadow.cal_q1_ref),
                    'cal_i_threshold': int(self.mirror.shadow.cal_i_threshold),
                    'cal_state_polarity': int(self.mirror.shadow.cal_state_polarity),
                    'cal_i0q0_valid': int(self.mirror.shadow.cal_i0q0_valid),
                    'cal_i1q1_valid': int(self.mirror.shadow.cal_i1q1_valid),
                    'cal_threshold_valid': int(self.mirror.shadow.cal_threshold_valid),
                    'meas_state': int(self.mirror.shadow.meas_state),
                    'meas_state_valid': int(self.mirror.shadow.meas_state_valid),
                },
                'play_cfgs': play_cfgs,
                'measure_cfgs': measure_cfgs,
                'instructions': instructions,
                'instructions_all_zero': all(word == 0 for word in self.mirror.shadow.instr_words),
                'instructions_any_valid': any(int(v) != 0 for v in self.mirror.shadow.instr_valid),
            }
