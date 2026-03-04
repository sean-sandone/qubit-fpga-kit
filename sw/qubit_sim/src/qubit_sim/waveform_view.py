import argparse
import numpy as np
import matplotlib.pyplot as plt


def make_envelope(t: np.ndarray, env: str, duration_s: float, sigma_s: float | None = None) -> np.ndarray:
    if env == "square":
        return ((t >= 0.0) & (t < duration_s)).astype(float)

    if env == "gauss":
        # Gaussian centered in the pulse window, clipped to the window
        if sigma_s is None:
            sigma_s = duration_s / 6.0
        center = duration_s / 2.0
        g = np.exp(-0.5 * ((t - center) / sigma_s) ** 2)
        win = ((t >= 0.0) & (t < duration_s)).astype(float)
        g = g * win
        # Normalize peak to 1
        mx = float(np.max(g)) if g.size else 1.0
        return g / mx if mx > 0 else g

    raise ValueError(f"Unknown env: {env}")


def generate_iq(
    fs_hz: float,
    duration_s: float,
    amp: float,
    phase_rad: float,
    if_hz: float,
    env: str = "square",
    sigma_s: float | None = None,
    pad_s: float = 0.0,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """
    Returns t, env, I, Q sampled at fs_hz over [0, duration + pad].
    """
    total_s = duration_s + pad_s
    n = int(np.ceil(total_s * fs_hz))
    n = max(n, 2)
    t = np.arange(n) / fs_hz

    e = make_envelope(t, env=env, duration_s=duration_s, sigma_s=sigma_s)

    # Typical FPGA pulse player model: envelope times NCO sin/cos at IF
    I = amp * e * np.cos(2.0 * np.pi * if_hz * t + phase_rad)
    Q = amp * e * np.sin(2.0 * np.pi * if_hz * t + phase_rad)
    return t, e, I, Q


def plot_envelope_and_iq(t: np.ndarray, e: np.ndarray, I: np.ndarray, Q: np.ndarray, title: str = "") -> None:
    # Envelope plot
    plt.figure()
    plt.plot(t * 1e9, e)
    plt.xlabel("Time (ns)")
    plt.ylabel("Envelope")
    plt.title(title + "Envelope" if title else "Envelope")
    plt.grid(True)

    # I/Q plot
    plt.figure()
    plt.plot(t * 1e9, I, label="I")
    plt.plot(t * 1e9, Q, label="Q")
    plt.xlabel("Time (ns)")
    plt.ylabel("Amplitude")
    plt.title(title + "I/Q samples" if title else "I/Q samples")
    plt.grid(True)
    plt.legend()

    plt.show()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fs", type=float, default=250e6, help="Sample rate in Hz")
    ap.add_argument("--dur", type=float, default=200e-9, help="Pulse duration in seconds")
    ap.add_argument("--amp", type=float, default=0.6, help="Amplitude (0..1)")
    ap.add_argument("--phase", type=float, default=0.0, help="Phase in radians")
    ap.add_argument("--if_hz", type=float, default=50e6, help="IF frequency in Hz")
    ap.add_argument("--env", type=str, default="square", choices=["square", "gauss"], help="Envelope type")
    ap.add_argument("--sigma", type=float, default=None, help="Gaussian sigma in seconds (gauss only)")
    ap.add_argument("--pad", type=float, default=200e-9, help="Extra time after pulse for plotting (seconds)")
    args = ap.parse_args()

    t, e, I, Q = generate_iq(
        fs_hz=args.fs,
        duration_s=args.dur,
        amp=args.amp,
        phase_rad=args.phase,
        if_hz=args.if_hz,
        env=args.env,
        sigma_s=args.sigma,
        pad_s=args.pad,
    )

    title = f"{args.env} env, dur={args.dur*1e9:.1f} ns, fs={args.fs/1e6:.1f} MS/s, IF={args.if_hz/1e6:.1f} MHz, amp={args.amp}"
    plot_envelope_and_iq(t, e, I, Q, title=title + "\n")


if __name__ == "__main__":
    main()