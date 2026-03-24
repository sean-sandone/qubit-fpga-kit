from __future__ import annotations

from flask import Flask, jsonify, redirect, render_template_string, request, url_for

from .waveform_viewer import WaveformViewerApp


PAGE_HTML = """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Quantum FPGA Control Panel</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #0b1020;
      --panel: #151c31;
      --panel2: #1d2742;
      --border: #304264;
      --text: #e8eefc;
      --muted: #a8b6d8;
      --accent: #74b0ff;
      --ok: #65d6a4;
      --warn: #ffcf70;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: Arial, Helvetica, sans-serif;
      background: linear-gradient(180deg, #0a0f1d 0%, #10172a 100%);
      color: var(--text);
    }
    .page {
      max-width: 1800px;
      margin: 0 auto;
      padding: 20px;
    }
    .topbar {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 16px;
      margin-bottom: 18px;
      flex-wrap: wrap;
    }
    .actions { display: flex; gap: 10px; flex-wrap: wrap; }
    button {
      background: var(--panel2);
      color: var(--text);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 10px 14px;
      cursor: pointer;
      font-weight: 600;
    }
    button:hover { border-color: var(--accent); }
    .layout {
      display: grid;
      grid-template-columns: minmax(620px, 625px) minmax(420px, 1fr);
      gap: 18px;
      align-items: start;
    }
    .panel {
      background: rgba(21, 28, 49, 0.95);
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 16px;
      box-shadow: 0 10px 40px rgba(0, 0, 0, 0.25);
    }
    .cards {
      display: grid;
      gap: 14px;
    }
    .play-card {
      background: rgba(29, 39, 66, 0.75);
      border: 1px solid var(--border);
      border-radius: 14px;
      padding: 14px;
    }
    .card-head {
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      gap: 12px;
      margin-bottom: 10px;
    }
    .summary {
      font-family: Consolas, Monaco, monospace;
      color: var(--muted);
      font-size: 13px;
      line-height: 1.5;
      white-space: pre-wrap;
    }
    .not-programmed {
      font-family: Consolas, Monaco, monospace;
      color: var(--warn);
      font-size: 14px;
      line-height: 1.5;
      white-space: pre-wrap;
      padding: 8px 0;
    }
    .thumb-row {
      display: flex;
      gap: 12px;
      flex-wrap: wrap;
      margin-top: 12px;
    }
    .thumb {
      position: relative;
      display: inline-block;
      padding: 8px;
      border-radius: 12px;
      background: #0f1526;
      border: 1px solid var(--border);
    }
    .thumb img.small {
      display: block;
      width: 250px;
      height: auto;
      border-radius: 8px;
    }
    .thumb .large {
      display: none;
      position: absolute;
      left: 0;
      top: calc(100% + 10px);
      z-index: 50;
      width: 720px;
      max-width: min(720px, 80vw);
      border: 1px solid var(--accent);
      border-radius: 10px;
      background: #0b1020;
      box-shadow: 0 18px 50px rgba(0, 0, 0, 0.5);
    }
    .thumb:hover .large { display: block; }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 14px;
    }
    th, td {
      border-bottom: 1px solid var(--border);
      padding: 8px 6px;
      text-align: left;
    }
    th { color: var(--muted); }
    .status-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 8px 16px;
      font-family: Consolas, Monaco, monospace;
      font-size: 14px;
    }
    .note {
      margin-top: 10px;
      color: var(--warn);
      font-size: 13px;
      line-height: 1.5;
    }
    @media (max-width: 1300px) {
      .layout { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
<div class="page">
  <div class="topbar">
    <div>
      <h1 style="margin:0; font-size:28px;">Quantum FPGA Control Panel</h1>
      <div style="color: var(--muted); margin-top: 6px;">Live view of mirrored UART register writes and generated pulse previews.</div>
    </div>
    <div class="actions">
      <form method="post" action="{{ url_for('action_route') }}">
        <input type="hidden" name="action" value="reload_shadow">
        <button type="submit">Reload shadow defaults</button>
      </form>
      <form method="post" action="{{ url_for('action_route') }}">
        <input type="hidden" name="action" value="send_all">
        <button type="submit">Send all registers</button>
      </form>
      <form method="post" action="{{ url_for('action_route') }}">
        <input type="hidden" name="action" value="start_exp">
        <button type="submit">Start experiment</button>
      </form>
      <form method="post" action="{{ url_for('action_route') }}">
        <input type="hidden" name="action" value="soft_reset">
        <button type="submit">Soft reset</button>
      </form>
    </div>
  </div>

  <div class="layout">
    <div class="panel">
      <h2 style="margin-top:0;">Play Config Registers</h2>
      <div class="cards">
        {% for cfg in state.play_cfgs %}
        <div class="play-card" id="playcfg-{{ cfg.index }}">
          <div class="card-head">
            <div>
              <strong>PlayCfg[{{ cfg.index }}]</strong>
            </div>
          </div>

          {% if cfg.is_programmed %}
          <div class="summary">amp_q8_8={{ cfg.summary.amp_q8_8 }} ({{ '%.6f'|format(cfg.summary.amp_float) }})
phase_q8_8={{ cfg.summary.phase_q8_8 }} ({{ '%.6f'|format(cfg.summary.phase_rad) }} rad)
duration_ns={{ cfg.summary.duration_ns }} sigma_ns={{ cfg.summary.sigma_ns }} pad_ns={{ cfg.summary.pad_ns }}
detune_hz={{ cfg.summary.detune_hz }} envelope={{ cfg.summary.envelope }}</div>

          <div class="thumb-row">
            <div class="thumb">
              <div style="margin-bottom: 6px; color: var(--muted);">Envelope</div>
              <img class="small" src="{{ cfg.preview.env_thumb }}" alt="Envelope thumbnail {{ cfg.index }}">
              <img class="large" src="{{ cfg.preview.env_large }}" alt="Envelope large {{ cfg.index }}">
            </div>
            <div class="thumb">
              <div style="margin-bottom: 6px; color: var(--muted);">I/Q</div>
              <img class="small" src="{{ cfg.preview.iq_thumb }}" alt="IQ thumbnail {{ cfg.index }}">
              <img class="large" src="{{ cfg.preview.iq_large }}" alt="IQ large {{ cfg.index }}">
            </div>
          </div>
          {% else %}
          <div class="not-programmed">Not programed</div>
          {% endif %}
        </div>
        {% endfor %}
      </div>
    </div>

    <div style="display:grid; gap: 18px; align-content:start;">
      <div class="panel">
        <h2 style="margin-top:0;">Control / Status</h2>
        <div class="status-grid">
          <div>start_exp</div><div>{{ state.control.start_exp }}</div>
          <div>soft_reset</div><div>{{ state.control.soft_reset }}</div>
          <div>reset_wait_cycles</div><div>{{ state.control.reset_wait_cycles }}</div>
          <div>captured_packets</div><div>{{ state.control.captured_packets }}</div>
        </div>
      </div>

      <div class="panel">
        <h2 style="margin-top:0;">Measure Config Registers</h2>
        <table>
          <thead>
            <tr><th>Idx</th><th>n_readout</th><th>readout_ns</th><th>ringup_ns</th></tr>
          </thead>
          <tbody>
            {% for cfg in state.measure_cfgs %}
            <tr>
              <td>{{ cfg.index }}</td>
              <td>{{ cfg.n_readout }}</td>
              <td>{{ cfg.readout_ns }}</td>
              <td>{{ cfg.ringup_ns }}</td>
            </tr>
            {% endfor %}
          </tbody>
        </table>
      </div>

      <div class="panel">
        <h2 style="margin-top:0;">Instruction Memory</h2>

        {% if state.instructions_all_zero %}
        <div class="note">
          Current mirrored instruction shadow is all zeros. This is coming from uart_menu.py, where instr_words is initialized to 0 and no default instruction program is loaded.
        </div>
        {% endif %}

        <table>
          <thead>
            <tr><th>Idx</th><th>Word</th><th>Opcode</th><th>Flags</th><th>Cfg</th><th>Operand</th></tr>
          </thead>
          <tbody>
            {% for instr in state.instructions %}
            <tr>
              <td>{{ instr.index }}</td>
              <td>{{ instr.word_hex }}</td>
              <td>{{ instr.opcode_name }}</td>
              <td>{{ instr.flags }}</td>
              <td>{{ instr.cfg }}</td>
              <td>{{ instr.operand }}</td>
            </tr>
            {% endfor %}
          </tbody>
        </table>
      </div>
    </div>
  </div>
</div>
</body>
</html>
"""


class WebUiApp:
    def __init__(self, host: str = '127.0.0.1', port: int = 5000, fs_hz: float = 1.0e9, if_hz: float = 50.0e6):
        self.host = host
        self.port = int(port)
        self.viewer = WaveformViewerApp(fs_hz=fs_hz, if_hz=if_hz)
        self.app = Flask(__name__)
        self._register_routes()

    def _register_routes(self) -> None:
        @self.app.get('/')
        def index():
            return render_template_string(PAGE_HTML, state=self.viewer.get_state_snapshot())

        @self.app.get('/api/state')
        def api_state():
            return jsonify(self.viewer.get_state_snapshot())

        @self.app.post('/action')
        def action_route():
            action = str(request.form.get('action', '')).strip().lower()
            if action == 'reload_shadow':
                self.viewer.reload_from_menu_shadow()
            elif action == 'send_all':
                self.viewer.send_all_registers()
            elif action == 'start_exp':
                self.viewer.send_start_experiment()
            elif action == 'soft_reset':
                self.viewer.send_soft_reset()
            return redirect(url_for('index'))

        self.action_route = action_route

    def attach_menu(self, menu) -> None:
        self.viewer.attach_menu(menu)

    def load_from_shadow(self, menu) -> None:
        self.viewer.load_from_shadow(menu)

    def post_packet(self, label: str, packet: bytes) -> None:
        self.viewer.post_packet(label, packet)

    def run(self) -> None:
        self.app.run(host=self.host, port=self.port, debug=False, use_reloader=False)

def _main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Run the Quantum FPGA web UI")
    parser.add_argument("--host", default="127.0.0.1", help="Bind host")
    parser.add_argument("--port", type=int, default=5000, help="HTTP port")
    parser.add_argument("--fs_hz", type=float, default=1.0e9, help="Waveform preview sample rate")
    parser.add_argument("--if_hz", type=float, default=50.0e6, help="Waveform preview IF in Hz")
    args = parser.parse_args()

    app = WebUiApp(
        host=args.host,
        port=args.port,
        fs_hz=args.fs_hz,
        if_hz=args.if_hz,
    )
    app.run()

if __name__ == "__main__":
    _main()