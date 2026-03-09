import numpy as np
from qutip import (
    basis,
    sigmax,
    sigmay,
    sigmaz,
    sigmam,
    mesolve,
    expect,
)


def iq_to_complex_envelope(
    t: np.ndarray,
    I_wave: np.ndarray,
    Q_wave: np.ndarray,
    if_hz: float,
) -> np.ndarray:
    """
    Convert DAC-style IF I/Q samples into a baseband complex envelope u(t).

    u(t) = (I + jQ) * exp(-j 2π f_if t)

    This is a modeling convenience so the qubit simulator can consume the slow baseband drive
    instead of the fast carrier.
    """
    t = np.asarray(t, dtype=float)
    I_wave = np.asarray(I_wave, dtype=float)
    Q_wave = np.asarray(Q_wave, dtype=float)
    if I_wave.shape != Q_wave.shape or I_wave.shape != t.shape:
        raise ValueError("t, I_wave, and Q_wave must have the same shape")

    s = I_wave + 1j * Q_wave
    lo = np.exp(-1j * 2.0 * np.pi * float(if_hz) * t)
    return s * lo


class QubitSim:
    """
    QubitSim models a 1-qubit device with decoherence and a simple readout model.

    Two separate I/Q concepts:

    1) Drive I/Q waveforms: time-series samples I_wave[n], Q_wave[n] from VirtualFPGA.render_iq()
       These represent what would go to a dual DAC in a lab.

    2) Readout I/Q: a single integrated measurement point (I_meas, Q_meas) returned per shot.

    Typical flow with virtual_fpga:
      t, env, I_wave, Q_wave = fpga.render_iq(pulse)
      I_meas, Q_meas = sim.measure_from_iq(t, I_wave, Q_wave, if_hz=fpga.if_hz)
    """

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

        # Scale factor that maps the dimensionless envelope u(t) into rad/s drive strength
        self.omega_max = 2.0 * np.pi * float(omega_max_hz)  # rad/s

        self.readout_mu0 = float(readout_mu0)
        self.readout_mu1 = float(readout_mu1)
        self.readout_sigma = float(readout_sigma)

        # State stored as a density matrix for easy inclusion of decoherence
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

    # ----------------------------
    # Parameter-level pulse model
    # ----------------------------

    def _envelope_value(self, t: float, tp: float, env: str, sigma: float | None = None, **_kwargs) -> float:
        if env == "square":
            return 1.0 if 0.0 <= t <= tp else 0.0

        if env == "gauss":
            if sigma is None:
                sigma = tp / 6.0
            center = tp / 2.0
            return float(np.exp(-0.5 * ((t - center) / sigma) ** 2))

        raise ValueError(f"Unknown env {env}")

    def pulse_p1(self, pulse: dict, n_steps: int = 200) -> float:
        """
        Fast path: evolve using pulse parameters directly (no explicit I/Q waveform).

        pulse fields:
          amp: 0..1
          phase: radians
          duration: seconds
          env: "square" or "gauss"
          sigma: seconds (optional for gauss)
          detuning_hz: Hz (optional)

        Returns p1 = P(|1>) and updates internal state self.rho.
        """
        amp = float(pulse["amp"])
        phase = float(pulse.get("phase", 0.0))
        tp = float(pulse["duration"])

        if tp <= 0.0:
            return float(expect(self.P1, self.rho))

        det_hz = float(pulse.get("detuning_hz", 0.0))
        env = pulse.get("env", "square")

        H0 = 0.5 * (2.0 * np.pi * det_hz) * sigmaz()
        Haxis = np.cos(phase) * sigmax() + np.sin(phase) * sigmay()
        H1 = 0.5 * Haxis

        Omega = amp * self.omega_max
        args = {"tp": tp, "env": env}
        if "sigma" in pulse:
            args["sigma"] = float(pulse["sigma"])

        H = [H0, [Omega * H1, self._envelope_value]]

        n_steps = int(max(10, n_steps))
        tlist = np.linspace(0.0, tp, n_steps)

        res = mesolve(
            H,
            self.rho,
            tlist,
            c_ops=self.c_ops,
            e_ops=[self.P1],
            args=args,
            options={"store_states": True},
        )

        if not hasattr(res, "states") or len(res.states) == 0:
            raise RuntimeError("mesolve returned no states in pulse_p1")
    
        self.rho = res.states[-1]
        return float(res.expect[0][-1])

    def measure(self, pulse: dict):
        """
        Fast path measurement using pulse parameters.
        Returns a single-shot readout point (I_meas, Q_meas).
        """
        p1 = self.pulse_p1(pulse)
        return self._sample_readout_iq(p1)

    # -----------------------------------------
    # Waveform-driven model (VirtualFPGA input)
    # -----------------------------------------

    def pulse_p1_from_envelope(
        self,
        t: np.ndarray,
        u: np.ndarray,
        detuning_hz: float = 0.0,
        max_points: int | None = 5000,
    ) -> float:
        """
        Evolve under a baseband complex envelope u(t) sampled at times t.

        u(t) is dimensionless, typically u(t) ~= amp * env(t) * exp(j * phase(t)).

        max_points: if not None and len(t) is larger than this, we downsample for speed.
        """
        t = np.asarray(t, dtype=float)
        u = np.asarray(u, dtype=complex)
        if t.ndim != 1 or u.ndim != 1 or t.shape != u.shape:
            raise ValueError("t and u must be 1D arrays with the same length")

        if len(t) < 2:
            return float(expect(self.P1, self.rho))

        # Optional downsample for performance
        if max_points is not None and len(t) > int(max_points):
            step = int(np.ceil(len(t) / int(max_points)))
            t = t[::step]
            u = u[::step]

        # Ensure time starts at 0 for the piecewise index mapping
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

        # H = (Δ/2) sz + (omega_max/2) * ( Re(u)*sx + Im(u)*sy )
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

    def current_p1(self) -> float:
        """
        Return current excited-state population P(|1>) from the stored state.
        """
        return float(expect(self.P1, self.rho))

    def readout_iq(self):
        """
        Measure the current state and return one noisy integrated readout point.
        Does not change self.rho.
        """
        p1 = self.current_p1()
        return self._sample_readout_iq(p1)

    def readout_waveform(
        self,
        n_readout: int = 64,
        readout_duration_s: float = 1.0e-6,
        ringup_fraction: float = 0.2,
    ):
        """
        Measure the current state and return a short readout waveform.
        Does not change self.rho.
        """
        p1 = self.current_p1()
        return self._sample_readout_waveform(
            p1,
            n_readout=n_readout,
            readout_duration_s=readout_duration_s,
            ringup_fraction=ringup_fraction,
        )

    def measure_from_envelope(
        self,
        t: np.ndarray,
        u: np.ndarray,
        detuning_hz: float = 0.0,
        max_points: int | None = 5000,
    ):
        """
        Apply a baseband complex envelope u(t) and return one readout point (I_meas, Q_meas).
        """
        p1 = self.pulse_p1_from_envelope(t, u, detuning_hz=detuning_hz, max_points=max_points)
        return self._sample_readout_iq(p1)

    def measure_from_iq(
        self,
        t: np.ndarray,
        I_wave: np.ndarray,
        Q_wave: np.ndarray,
        if_hz: float,
        detuning_hz: float = 0.0,
        max_points: int | None = 5000,
    ):
        """
        Main integration point with VirtualFPGA.

        Takes DAC-style IF I/Q waveforms, converts them to baseband complex envelope u(t),
        evolves the qubit, and returns a single readout point (I_meas, Q_meas).
        """
        u = iq_to_complex_envelope(t, I_wave, Q_wave, if_hz=float(if_hz))
        return self.measure_from_envelope(t, u, detuning_hz=detuning_hz, max_points=max_points)

    def measure_waveform_from_envelope(
        self,
        t: np.ndarray,
        u: np.ndarray,
        detuning_hz: float = 0.0,
        max_points: int | None = 5000,
        n_readout: int = 64,
        readout_duration_s: float = 1.0e-6,
        ringup_fraction: float = 0.2,
    ):
        """
        Apply a baseband complex envelope u(t) and return a short readout waveform.

        Returns:
          t_ro: readout time axis, shape (n_readout,)
          I_ro: readout I samples, shape (n_readout,)
          Q_ro: readout Q samples, shape (n_readout,)

        This models the post-ADC/post-downconversion readout stream that an FPGA might integrate.
        It is intentionally simple: choose a single-shot outcome from p1, generate a state-dependent
        complex mean, apply a first-order ring-up, and add white Gaussian noise.
        """
        p1 = self.pulse_p1_from_envelope(t, u, detuning_hz=detuning_hz, max_points=max_points)
        return self._sample_readout_waveform(
            p1,
            n_readout=n_readout,
            readout_duration_s=readout_duration_s,
            ringup_fraction=ringup_fraction,
        )

    def measure_waveform_from_iq(
        self,
        t: np.ndarray,
        I_wave: np.ndarray,
        Q_wave: np.ndarray,
        if_hz: float,
        detuning_hz: float = 0.0,
        max_points: int | None = 5000,
        n_readout: int = 64,
        readout_duration_s: float = 1.0e-6,
        ringup_fraction: float = 0.2,
    ):
        """
        Main waveform-returning integration point with VirtualFPGA.

        Takes DAC-style IF I/Q waveforms, converts them to a baseband complex envelope u(t),
        evolves the qubit, and returns a short readout waveform (t_ro, I_ro, Q_ro).
        """
        u = iq_to_complex_envelope(t, I_wave, Q_wave, if_hz=float(if_hz))
        return self.measure_waveform_from_envelope(
            t,
            u,
            detuning_hz=detuning_hz,
            max_points=max_points,
            n_readout=n_readout,
            readout_duration_s=readout_duration_s,
            ringup_fraction=ringup_fraction,
        )

    # ----------------------------
    # Readout model
    # ----------------------------

    def _sample_readout_iq(self, p1: float):
        """
        Simple readout: sample a projective outcome using p1, then generate a noisy (I_meas, Q_meas).
        """
        p1 = float(np.clip(p1, 0.0, 1.0))
        outcome_is_1 = self.rng.random() < p1
        muI = self.readout_mu1 if outcome_is_1 else self.readout_mu0

        I_meas = muI + self.readout_sigma * self.rng.standard_normal()
        Q_meas = 0.0 + self.readout_sigma * self.rng.standard_normal()
        return (I_meas, Q_meas)
    
    # ----------------------------
    # Readout waveform 
    # ----------------------------

    def _sample_readout_waveform(
        self,
        p1: float,
        n_readout: int = 64,
        readout_duration_s: float = 1.0e-6,
        ringup_fraction: float = 0.2,
    ):
        """
        Generate a short post-downconversion readout waveform.

        Returns:
          t_ro: shape (n_readout,)
          I_ro: shape (n_readout,)
          Q_ro: shape (n_readout,)
        """
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
    