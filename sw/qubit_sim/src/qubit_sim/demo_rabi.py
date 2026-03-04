import argparse
import numpy as np
import matplotlib.pyplot as plt

from qubit_sim.qubit_model import QubitSim, iq_to_complex_envelope
from qubit_sim.virtual_fpga import VirtualFPGA
from qubit_sim.waveform_view import plot_envelope_and_iq, plot_rabi


def sample_readout_iq(sim: QubitSim, p1: float):
    """Generate one synthetic readout point (I_meas, Q_meas) from probability p1."""
    p1 = float(np.clip(p1, 0.0, 1.0))
    outcome_is_1 = sim.rng.random() < p1
    muI = sim.readout_mu1 if outcome_is_1 else sim.readout_mu0
    I_meas = muI + sim.readout_sigma * sim.rng.standard_normal()
    Q_meas = 0.0 + sim.readout_sigma * sim.rng.standard_normal()
    return I_meas, Q_meas


def make_p1_provider_param(sim_model: QubitSim, pulse_base: dict):
    def p1_for_duration(tp: float) -> float:
        sim_model.reset()
        pulse = dict(pulse_base)
        pulse["duration"] = float(tp)
        return sim_model.pulse_p1(pulse)
    return p1_for_duration


def make_p1_provider_fpga(sim_model: QubitSim, fpga: VirtualFPGA, pulse_base: dict, pad_s: float):
    def p1_for_duration(tp: float) -> float:
        sim_model.reset()
        pulse = dict(pulse_base)
        pulse["duration"] = float(tp)

        t, env, Iw, Qw = fpga.render_iq(pulse, pad_s=float(pad_s))
        u = iq_to_complex_envelope(t, Iw, Qw, if_hz=fpga.if_hz)
        return sim_model.pulse_p1_from_envelope(t, u)
    return p1_for_duration


def run_rabi_binomial(p1_provider, durations, shots: int):
    """Fast: one p1 solve per duration, then binomial shot sampling."""
    p1_true = []
    p1_est = []

    for i, tp in enumerate(durations):
        p1 = float(p1_provider(float(tp)))
        p1_true.append(p1)

        ones = np.random.binomial(shots, p1)
        p1_est.append(ones / shots)

        if i % 10 == 0:
            print(f"{i+1}/{len(durations)} done")

    return np.array(p1_true), np.array(p1_est)


def run_rabi_threshold(sim_meas: QubitSim, p1_provider, durations, shots: int, threshold: float):
    """
    Thresholded readout: one p1 solve per duration, then generate (I_meas, Q_meas) shots and threshold I_meas.
    This stays fast and looks like real discriminator logic.
    """
    p1_true = []
    p1_est = []

    for i, tp in enumerate(durations):
        p1 = float(p1_provider(float(tp)))
        p1_true.append(p1)

        ones = 0
        for _ in range(shots):
            I_meas, Q_meas = sample_readout_iq(sim_meas, p1)
            ones += 1 if I_meas > threshold else 0

        p1_est.append(ones / shots)

        if i % 10 == 0:
            print(f"{i+1}/{len(durations)} done")

    return np.array(p1_true), np.array(p1_est)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--drive_source", type=str, default="param", choices=["param", "fpga"])
    ap.add_argument("--omega_max_hz", type=float, default=2e6)
    ap.add_argument("--amp", type=float, default=1.0)
    ap.add_argument("--phase", type=float, default=0.0)
    ap.add_argument("--envelope", type=str, default="square", choices=["square", "gauss"])
    ap.add_argument("--sigma", type=float, default=None, help="Seconds, for gauss envelope only")
    ap.add_argument("--t_end", type=float, default=2e-6, help="Seconds")
    ap.add_argument("--points", type=int, default=81)
    ap.add_argument("--shots", type=int, default=2000)
    ap.add_argument("--mode", type=str, default="binomial", choices=["binomial", "threshold"])
    ap.add_argument("--threshold", type=float, default=0.0)
    ap.add_argument("--show_waveform", action="store_true")

    # VirtualFPGA params (used when drive_source=fpga, and for waveform display)
    ap.add_argument("--fs_hz", type=float, default=250e6)
    ap.add_argument("--if_hz", type=float, default=50e6)
    ap.add_argument("--pad_s", type=float, default=200e-9)

    args = ap.parse_args()

    # Base pulse settings (duration swept)
    pulse_base = {
        "amp": float(args.amp),
        "phase": float(args.phase),
        "duration": 0.0,
        "envelope": args.envelope,
    }
    if args.sigma is not None:
        pulse_base["sigma"] = float(args.sigma)

    durations = np.linspace(0.0, float(args.t_end), int(args.points))

    # Sims
    sim_model = QubitSim(seed=1, omega_max_hz=float(args.omega_max_hz))
    sim_meas = QubitSim(seed=2, omega_max_hz=float(args.omega_max_hz))

    fpga = None
    if args.drive_source == "fpga" or args.show_waveform:
        fpga = VirtualFPGA(fs_hz=float(args.fs_hz), if_hz=float(args.if_hz))

    # Optional waveform plot (use midpoint duration)
    if args.show_waveform:
        pulse = dict(pulse_base)
        pulse["duration"] = float(durations[len(durations) // 2])
        t, env, I_wave, Q_wave = fpga.render_iq(pulse, pad_s=float(args.pad_s))
        plot_envelope_and_iq(t, env, I_wave, Q_wave, unit="ns", title_prefix="VirtualFPGA ")

    # Choose how we compute p1 for each duration
    if args.drive_source == "param":
        p1_provider = make_p1_provider_param(sim_model, pulse_base)
    else:
        p1_provider = make_p1_provider_fpga(sim_model, fpga, pulse_base, pad_s=float(args.pad_s))

    # Run experiment
    if args.mode == "binomial":
        p1_true, p1_est = run_rabi_binomial(p1_provider, durations, shots=int(args.shots))
        label = f"binomial shots={args.shots}"
    else:
        p1_true, p1_est = run_rabi_threshold(
            sim_meas, p1_provider, durations, shots=int(args.shots), threshold=float(args.threshold)
        )
        label = f"threshold shots={args.shots}"

    # Plot results
    plot_rabi(
        durations,
        p1_true,
        p1_est,
        unit="us",
        title=f"Rabi ({args.drive_source} drive, {args.envelope} env, amp={args.amp}, omega_max_hz={args.omega_max_hz:g})",
        est_label=label,
    )
    plt.show()


if __name__ == "__main__":
    main()