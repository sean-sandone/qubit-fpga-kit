#!/usr/bin/env python3
##------------------------------------------------------------------------------
## PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
##------------------------------------------------------------------------------
## AUTHORS: Sean Sandone
## WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
##------------------------------------------------------------------------------

import argparse
import math
from dataclasses import dataclass

import numpy as np
from qutip import basis, expect, mesolve, sigmam, sigmax, sigmay, sigmaz


AmpFullScale = 0x0100
PhaseTurnScale = 0x10000
NsPerSecond = 1.0e9
DefaultInstrClockHz = 125e6


def iq_to_complex_envelope(
    t: np.ndarray,
    I_wave: np.ndarray,
    Q_wave: np.ndarray,
    if_hz: float,
) -> np.ndarray:
    t = np.asarray(t, dtype=float)
    I_wave = np.asarray(I_wave, dtype=float)
    Q_wave = np.asarray(Q_wave, dtype=float)

    if I_wave.shape != Q_wave.shape or I_wave.shape != t.shape:
        raise ValueError("t, I_wave, and Q_wave must have the same shape")

    s = I_wave + 1j * Q_wave
    lo = np.exp(-1j * 2.0 * np.pi * float(if_hz) * t)
    return s * lo


class VirtualFPGA:
    def __init__(self, fs_hz: float, if_hz: float):
        self.fs_hz = float(fs_hz)
        self.if_hz = float(if_hz)

    def envelope_samples(self, t: np.ndarray, pulse: dict) -> np.ndarray:
        tp = float(pulse["duration"])
        envelope = pulse.get("envelope", "square")

        if envelope == "square":
            return ((t >= 0.0) & (t < tp)).astype(float)

        if envelope == "gauss":
            sigma = float(pulse.get("sigma", tp / 6.0))
            center = tp / 2.0
            g = np.exp(-0.5 * ((t - center) / sigma) ** 2)
            win = ((t >= 0.0) & (t < tp)).astype(float)
            g = g * win
            mx = float(np.max(g)) if g.size else 1.0
            return g / mx if mx > 0 else g

        raise ValueError(f"Unknown envelope shape: {envelope}")

    def render_iq(self, pulse: dict, pad_s: float = 0.0):
        amp = float(pulse["amp"])
        phase = float(pulse.get("phase", 0.0))
        tp = float(pulse["duration"])
        pad_s = float(pad_s)

        total_s = tp + pad_s
        n = int(np.ceil(total_s * self.fs_hz))
        n = max(n, 2)
        t = np.arange(n) / self.fs_hz

        env = self.envelope_samples(t, pulse)

        I_wave = amp * env * np.cos(2.0 * np.pi * self.if_hz * t + phase)
        Q_wave = amp * env * np.sin(2.0 * np.pi * self.if_hz * t + phase)
        return t, env, I_wave, Q_wave


class QubitSim:
    def __init__(
        self,
        omega_max_hz: float = 20e6,
        T1: float = 30e-6,
        T2: float = 20e-6,
        readout_mu0: float = -1.0,
        readout_mu1: float = +1.0,
        readout_sigma: float = 0.25,
        seed=None,
    ):
        self.rng = np.random.default_rng(seed)
        self.omega_max = 2.0 * np.pi * float(omega_max_hz)
        self.readout_mu0 = float(readout_mu0)
        self.readout_mu1 = float(readout_mu1)
        self.readout_sigma = float(readout_sigma)

        self.rho = basis(2, 0).proj()
        self.P1 = basis(2, 1).proj()

        gamma1 = 0.0 if T1 <= 0 else 1.0 / float(T1)
        gamma_phi = 0.0
        if T2 > 0 and T1 > 0:
            gamma_phi = max(0.0, 1.0 / float(T2) - 1.0 / (2.0 * float(T1)))

        self.c_ops = []
        if gamma1 > 0:
            self.c_ops.append(np.sqrt(gamma1) * sigmam())
        if gamma_phi > 0:
            self.c_ops.append(np.sqrt(gamma_phi) * sigmaz())

    def reset(self):
        self.rho = basis(2, 0).proj()

    def current_p1(self) -> float:
        return float(expect(self.P1, self.rho))

    def pulse_p1_from_envelope(
        self,
        t: np.ndarray,
        u: np.ndarray,
        detuning_hz: float = 0.0,
        max_points: int | None = 5000,
    ) -> float:
        t = np.asarray(t, dtype=float)
        u = np.asarray(u, dtype=complex)
        if t.ndim != 1 or u.ndim != 1 or t.shape != u.shape:
            raise ValueError("t and u must be 1D arrays with the same length")

        if len(t) < 2:
            return float(expect(self.P1, self.rho))

        if max_points is not None and len(t) > int(max_points):
            step = int(np.ceil(len(t) / int(max_points)))
            t = t[::step]
            u = u[::step]

        t0 = float(t[0])
        if abs(t0) > 1e-15:
            t = t - t0

        dt = float(t[1] - t[0])
        if dt <= 0:
            raise ValueError("t must be strictly increasing")

        n = int(len(u))

        def ux(tt, **_kwargs):
            idx = int(tt / dt)
            if idx < 0 or idx >= n:
                return 0.0
            return float(np.real(u[idx]))

        def uy(tt, **_kwargs):
            idx = int(tt / dt)
            if idx < 0 or idx >= n:
                return 0.0
            return float(np.imag(u[idx]))

        H0 = 0.5 * (2.0 * np.pi * float(detuning_hz)) * sigmaz()
        H = [
            H0,
            [0.5 * self.omega_max * sigmax(), ux],
            [0.5 * self.omega_max * sigmay(), uy],
        ]

        res = mesolve(
            H,
            self.rho,
            t,
            c_ops=self.c_ops,
            e_ops=[self.P1],
            options={"store_states": True},
        )

        if not hasattr(res, "states") or len(res.states) == 0:
            raise RuntimeError("mesolve returned no states in pulse_p1_from_envelope")

        self.rho = res.final_state
        return float(res.expect[0][-1])

    def readout_waveform(
        self,
        n_readout: int = 64,
        readout_duration_s: float = 1.0e-6,
        ringup_fraction: float = 0.2,
    ):
        p1 = self.current_p1()
        return self._sample_readout_waveform(
            p1,
            n_readout=n_readout,
            readout_duration_s=readout_duration_s,
            ringup_fraction=ringup_fraction,
        )

    def _sample_readout_waveform(
        self,
        p1: float,
        n_readout: int = 64,
        readout_duration_s: float = 1.0e-6,
        ringup_fraction: float = 0.2,
    ):
        n_readout = int(max(2, n_readout))
        readout_duration_s = float(readout_duration_s)
        if readout_duration_s <= 0.0:
            raise ValueError("readout_duration_s must be > 0")

        p1 = float(np.clip(p1, 0.0, 1.0))
        outcome_is_1 = self.rng.random() < p1

        muI = self.readout_mu1 if outcome_is_1 else self.readout_mu0
        muQ = 0.0

        t_ro = np.linspace(0.0, readout_duration_s, n_readout, endpoint=False)

        frac = float(np.clip(ringup_fraction, 1.0e-6, 1.0))
        tau = max(readout_duration_s * frac, 1.0e-15)
        env = 1.0 - np.exp(-t_ro / tau)

        I_ro = muI * env + self.readout_sigma * self.rng.standard_normal(n_readout)
        Q_ro = muQ * env + self.readout_sigma * self.rng.standard_normal(n_readout)

        return (t_ro, I_ro, Q_ro)


@dataclass(frozen=True)
class PlayCfg:
    amp_q8_8: int
    phase_q8_8: int
    duration_ns: int
    sigma_ns: int
    pad_ns: int
    detune_hz: int
    envelope: str

    def to_pulse(self) -> dict:
        pulse = {
            "amp": float(self.amp_q8_8) / float(AmpFullScale),
            "phase": (2.0 * math.pi * float(self.phase_q8_8 & 0xFFFF)) / float(PhaseTurnScale),
            "duration": float(self.duration_ns) / float(NsPerSecond),
            "envelope": self.envelope.lower(),
        }
        if self.sigma_ns > 0:
            pulse["sigma"] = float(self.sigma_ns) / float(NsPerSecond)
        return pulse

    @property
    def pad_s(self) -> float:
        return float(self.pad_ns) / float(NsPerSecond)


@dataclass(frozen=True)
class MeasureCfg:
    n_readout: int
    readout_ns: int
    ringup_ns: int

    @property
    def readout_duration_s(self) -> float:
        return float(self.readout_ns) / float(NsPerSecond)

    @property
    def ringup_fraction(self) -> float:
        if self.readout_ns <= 0:
            return 0.0
        return float(self.ringup_ns) / float(self.readout_ns)


PLAY_CFGS = {
    0: PlayCfg(
        amp_q8_8=0x0100,
        phase_q8_8=0x0000,
        duration_ns=200,
        sigma_ns=30,
        pad_ns=200,
        detune_hz=0,
        envelope="gauss",
    ),
    1: PlayCfg(
        amp_q8_8=0x0330,
        phase_q8_8=0x0000,
        duration_ns=200,
        sigma_ns=30,
        pad_ns=200,
        detune_hz=0,
        envelope="gauss",
    ),
    2: PlayCfg(
        amp_q8_8=0x0080,
        phase_q8_8=0x0100,
        duration_ns=200,
        sigma_ns=30,
        pad_ns=200,
        detune_hz=0,
        envelope="gauss",
    ),
}

MEASURE_CFGS = {
    0: MeasureCfg(n_readout=64, readout_ns=1024, ringup_ns=512),
    1: MeasureCfg(n_readout=64, readout_ns=1024, ringup_ns=256),
}

RESET_WAIT_CYCLES = 1000

ROM_PROGRAM = [
    ("WAIT_RESET", 0),
    ("MEASURE", 0),
    ("WAIT_RESET", 0),
    ("MEASURE", 0),
    ("WAIT_RESET", 0),
    ("MEASURE", 0),
    ("WAIT_RESET", 0),
    ("PLAY", 1),
    ("MEASURE", 1),
    ("WAIT_RESET", 0),
    ("PLAY", 1),
    ("MEASURE", 1),
    ("WAIT_RESET", 0),
    ("PLAY", 1),
    ("MEASURE", 1),
    ("WAIT_RESET", 0),
    ("PLAY", 1),
    ("MEASURE", 1),
    ("WAIT_RESET", 0),
    ("PLAY", 1),
    ("MEASURE", 1),
    ("WAIT_RESET", 0),
    ("PLAY", 1),
    ("MEASURE", 1),
    ("WAIT_RESET", 0),
    ("PLAY", 1),
    ("MEASURE", 1),
    ("WAIT_RESET", 0),
    ("PLAY", 0),
    ("WAIT", 100),
    ("PLAY", 2),
    ("MEASURE", 0),
    ("END", 0),
]


def summarize_waveform(I_vals: np.ndarray, Q_vals: np.ndarray) -> str:
    return (
        f"n={len(I_vals)} "
        f"I_avg={float(np.mean(I_vals)):.6f} "
        f"Q_avg={float(np.mean(Q_vals)):.6f} "
        f"I_min={float(np.min(I_vals)):.6f} "
        f"I_max={float(np.max(I_vals)):.6f} "
        f"Q_min={float(np.min(Q_vals)):.6f} "
        f"Q_max={float(np.max(Q_vals)):.6f}"
    )


def execute_play(cfg_idx: int, fpga: VirtualFPGA, sim: QubitSim, verbose: bool = True):
    cfg = PLAY_CFGS[cfg_idx]
    pulse = cfg.to_pulse()
    t, env, Iw, Qw = fpga.render_iq(pulse, pad_s=cfg.pad_s)
    u = iq_to_complex_envelope(t, Iw, Qw, if_hz=float(fpga.if_hz))
    p1 = sim.pulse_p1_from_envelope(t, u, detuning_hz=float(cfg.detune_hz))

    if verbose:
        print(
            "PLAY "
            f"cfg={cfg_idx} amp={pulse['amp']:.6f} phase_rad={pulse['phase']:.6f} "
            f"duration_ns={cfg.duration_ns} sigma_ns={cfg.sigma_ns} pad_ns={cfg.pad_ns} "
            f"detune_hz={cfg.detune_hz} envelope={cfg.envelope.upper()} p1_est={p1:.6f}"
        )

    return {
        "cfg": cfg_idx,
        "pulse": pulse,
        "p1_est": p1,
        "t": t,
        "env": env,
        "I_wave": Iw,
        "Q_wave": Qw,
    }


def execute_measure(cfg_idx: int, sim: QubitSim, verbose: bool = True):
    cfg = MEASURE_CFGS[cfg_idx]
    t_ro, I_ro, Q_ro = sim.readout_waveform(
        n_readout=cfg.n_readout,
        readout_duration_s=cfg.readout_duration_s,
        ringup_fraction=cfg.ringup_fraction,
    )

    p1_before_readout = sim.current_p1()

    if verbose:
        print(
            "MEASURE "
            f"cfg={cfg_idx} p1_before={p1_before_readout:.6f} "
            f"readout_ns={cfg.readout_ns} ringup_ns={cfg.ringup_ns} "
            f"{summarize_waveform(I_ro, Q_ro)}"
        )

    return {
        "cfg": cfg_idx,
        "p1_before": p1_before_readout,
        "t_ro": t_ro,
        "I_ro": I_ro,
        "Q_ro": Q_ro,
    }


def execute_rom_sequence(
    fs_hz: float = 250e6,
    if_hz: float = 50e6,
    omega_max_hz: float = 2e6,
    instr_clock_hz: float = DefaultInstrClockHz,
    seed: int = 1,
    verbose: bool = True,
):
    fpga = VirtualFPGA(fs_hz=fs_hz, if_hz=if_hz)
    sim = QubitSim(seed=seed, omega_max_hz=omega_max_hz)

    results = []

    if verbose:
        print("Loaded defaults from defaults_rom.sv")
        print(f"RESET_WAIT_CYCLES={RESET_WAIT_CYCLES}")
        print(f"RESET_WAIT_TIME_S={RESET_WAIT_CYCLES / float(instr_clock_hz):.9e}")
        print()

    for pc, instr in enumerate(ROM_PROGRAM):
        opcode, operand = instr

        if verbose:
            print(f"PC={pc:02d} OPCODE={opcode} OPERAND={operand}")

        if opcode == "WAIT_RESET":
            sim.reset()
            wait_s = RESET_WAIT_CYCLES / float(instr_clock_hz)
            result = {
                "pc": pc,
                "opcode": opcode,
                "cycles": RESET_WAIT_CYCLES,
                "wait_s": wait_s,
                "p1_after": sim.current_p1(),
            }
            if verbose:
                print(
                    f"  reset applied, modeled_wait_s={wait_s:.9e}, p1_after={result['p1_after']:.6f}"
                )
            results.append(result)
            continue

        if opcode == "WAIT":
            wait_s = int(operand) / float(instr_clock_hz)
            result = {
                "pc": pc,
                "opcode": opcode,
                "cycles": int(operand),
                "wait_s": wait_s,
                "p1_after": sim.current_p1(),
            }
            if verbose:
                print(
                    f"  idle wait only, modeled_wait_s={wait_s:.9e}, p1_after={result['p1_after']:.6f}"
                )
            results.append(result)
            continue

        if opcode == "PLAY":
            play_result = execute_play(int(operand), fpga, sim, verbose=verbose)
            play_result.update({"pc": pc, "opcode": opcode})
            results.append(play_result)
            continue

        if opcode == "MEASURE":
            measure_result = execute_measure(int(operand), sim, verbose=verbose)
            measure_result.update({"pc": pc, "opcode": opcode})
            results.append(measure_result)
            continue

        if opcode == "END":
            if verbose:
                print("  sequence complete")
            results.append({"pc": pc, "opcode": opcode})
            break

        raise ValueError(f"Unknown opcode {opcode!r} at pc={pc}")

        
    return results


def main():
    ap = argparse.ArgumentParser(
        description="Run the defaults_rom.sv command sequence directly against the QuTiP sim"
    )
    ap.add_argument("--fs_hz", type=float, default=250e6)
    ap.add_argument("--if_hz", type=float, default=50e6)
    ap.add_argument("--omega_max_hz", type=float, default=2e6)
    ap.add_argument("--instr_clock_hz", type=float, default=DefaultInstrClockHz)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    execute_rom_sequence(
        fs_hz=args.fs_hz,
        if_hz=args.if_hz,
        omega_max_hz=args.omega_max_hz,
        instr_clock_hz=args.instr_clock_hz,
        seed=args.seed,
        verbose=not args.quiet,
    )


if __name__ == "__main__":
    main()
