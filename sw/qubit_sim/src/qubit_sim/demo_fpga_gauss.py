import numpy as np
import matplotlib.pyplot as plt

from qubit_sim.virtual_fpga import VirtualFPGA
from qubit_sim.qubit_model import QubitSim, iq_to_complex_envelope


def main():
    # "Virtual FPGA" settings (DAC sample rate and IF)
    fs_hz = 250e6
    if_hz = 50e6

    fpga = VirtualFPGA(fs_hz=fs_hz, if_hz=if_hz)
    sim = QubitSim(seed=1, omega_max_hz=2e6)

    # Gaussian pulse definition for VirtualFPGA (note key name: "envelope")
    pulse = {
        "amp": 1.0,
        "phase": 0.0,
        "duration": 200e-9,     # 200 ns pulse
        "envelope": "gauss",    # must be "gauss" or "square"
        "sigma": 30e-9,         # 30 ns Gaussian sigma
    }

    # 1) Generate what would go to a dual DAC
    t, env, I_wave, Q_wave = fpga.render_iq(pulse, pad_s=200e-9)

    # Plot envelope and DAC sample streams
    plt.figure()
    plt.plot(t * 1e9, env)
    plt.xlabel("Time (ns)")
    plt.ylabel("Envelope")
    plt.title("Gaussian envelope (VirtualFPGA)")
    plt.grid(True)

    plt.figure()
    plt.plot(t * 1e9, I_wave, label="I_wave")
    plt.plot(t * 1e9, Q_wave, label="Q_wave")
    plt.xlabel("Time (ns)")
    plt.ylabel("Amplitude")
    plt.title("Drive I/Q samples (VirtualFPGA)")
    plt.grid(True)
    plt.legend()

    # 2) Feed the waveform into the qubit simulator and estimate P(|1|)
    # Convert IF I/Q to baseband complex envelope u(t)
    u = iq_to_complex_envelope(t, I_wave, Q_wave, if_hz=if_hz)

    # Underlying probability from the qubit model (one evolution)
    sim.reset()
    p1 = sim.pulse_p1_from_envelope(t, u)
    print(f"Model p1 after Gaussian pulse: {p1:.4f}")

    # Shot-based estimate using the sim readout (threshold on I_meas)
    shots = 2000
    ones = 0
    for _ in range(shots):
        sim.reset()
        I_meas, Q_meas = sim.measure_from_iq(t, I_wave, Q_wave, if_hz=if_hz)
        ones += 1 if I_meas > 0.0 else 0
    print(f"Threshold estimate over {shots} shots: {ones / shots:.4f}")

    plt.show()


if __name__ == "__main__":
    main()