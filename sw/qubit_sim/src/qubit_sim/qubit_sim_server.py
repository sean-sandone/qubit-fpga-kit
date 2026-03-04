import struct
from qubit_sim.qubit_model import QubitSim

def handle_play(sim: QubitSim, amp_u16, phase_i16, dur_ns_u32):
    # Example decoding (you can change formats)
    amp = amp_u16 / 65535.0
    phase = (phase_i16 / 32768.0) * 3.141592653589793
    duration = dur_ns_u32 * 1e-9

    I, Q = sim.apply_pulse({"amp": amp, "phase": phase, "duration": duration, "env": "square"})
    return I, Q

def run_dummy_demo():
    sim = QubitSim(seed=1)
    I, Q = sim.apply_pulse({"amp": 0.6, "phase": 0.0, "duration": 200e-9, "env": "square"})
    print(I, Q)

if __name__ == "__main__":
    run_dummy_demo()