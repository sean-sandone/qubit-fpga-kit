##------------------------------------------------------------------------------
## PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
##------------------------------------------------------------------------------
## Copyright (C) 2026 Sean Sandone
## SPDX-License-Identifier: AGPL-3.0-or-later
## Please see the LICENSE file for details.
## WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
##------------------------------------------------------------------------------

"""
Plot helpers for the qubit_sim demos.

Keep this module focused on plotting and visualization. Waveform synthesis lives in
VirtualFPGA (render_iq) and the qubit dynamics live in QubitSim.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import matplotlib.pyplot as plt


@dataclass(frozen=True)
class TimeAxis:
    scale: float
    label: str


_NS = TimeAxis(scale=1e9, label="Time (ns)")
_US = TimeAxis(scale=1e6, label="Time (us)")
_S = TimeAxis(scale=1.0, label="Time (s)")


def time_axis(unit: str) -> TimeAxis:
    """Return scaling and label for a time axis. unit: 'ns', 'us', or 's'."""
    u = unit.lower()
    if u == "ns":
        return _NS
    if u == "us":
        return _US
    if u == "s":
        return _S
    raise ValueError(f"Unknown time unit: {unit!r} (use 'ns', 'us', or 's')")


def plot_envelope(
    t_s: np.ndarray,
    env: np.ndarray,
    *,
    unit: str = "ns",
    title: str = "Envelope",
    figure: bool = True,
) -> None:
    ax_info = time_axis(unit)
    if figure:
        plt.figure()
    plt.plot(t_s * ax_info.scale, env)
    plt.xlabel(ax_info.label)
    plt.ylabel("Envelope")
    plt.title(title)
    plt.grid(True)


def plot_iq(
    t_s: np.ndarray,
    i_wave: np.ndarray,
    q_wave: np.ndarray,
    *,
    unit: str = "ns",
    title: str = "I/Q samples",
    labels: tuple[str, str] = ("I", "Q"),
    figure: bool = True,
) -> None:
    ax_info = time_axis(unit)
    if figure:
        plt.figure()
    plt.plot(t_s * ax_info.scale, i_wave, label=labels[0])
    plt.plot(t_s * ax_info.scale, q_wave, label=labels[1])
    plt.xlabel(ax_info.label)
    plt.ylabel("Amplitude")
    plt.title(title)
    plt.grid(True)
    plt.legend()


def plot_envelope_and_iq(
    t_s: np.ndarray,
    env: np.ndarray,
    i_wave: np.ndarray,
    q_wave: np.ndarray,
    *,
    unit: str = "ns",
    title_prefix: str = "Drive ",
) -> None:
    """Convenience wrapper used by the demos."""
    plot_envelope(t_s, env, unit=unit, title=f"{title_prefix}envelope")
    plot_iq(
        t_s,
        i_wave,
        q_wave,
        unit=unit,
        title=f"{title_prefix}I/Q samples",
        labels=("I_wave", "Q_wave"),
    )


def plot_rabi(
    durations_s: np.ndarray,
    p1_true: np.ndarray,
    p1_est: np.ndarray,
    *,
    unit: str = "us",
    title: str = "Rabi",
    est_label: str = "estimate",
    true_label: str = "p1 (model)",
    figure: bool = True,
) -> None:
    ax_info = time_axis(unit)
    if figure:
        plt.figure()
    plt.plot(durations_s * ax_info.scale, p1_true, linestyle="-", linewidth=2, label=true_label)
    plt.plot(durations_s * ax_info.scale, p1_est, marker="o", linestyle="None", label=est_label)
    plt.xlabel(f"Pulse duration ({unit})")
    plt.ylabel("P(|1>)")
    plt.title(title)
    plt.grid(True)
    plt.legend()