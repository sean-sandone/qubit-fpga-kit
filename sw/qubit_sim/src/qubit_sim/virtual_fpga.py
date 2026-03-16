##------------------------------------------------------------------------------
## PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
##------------------------------------------------------------------------------
## AUTHORS: Sean Sandone
## WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
##------------------------------------------------------------------------------

import numpy as np


class VirtualFPGA:
    """
    Generates DAC-style I/Q waveforms for a pulse, like an FPGA pulse player would.

    """

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
        """
        Returns:
          t (seconds), env (0..1), I_wave, Q_wave

        I_wave/Q_wave represent what would be streamed to a dual DAC.
        """
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

