##------------------------------------------------------------------------------
## PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
##------------------------------------------------------------------------------
## Copyright (C) 2026 Sean Sandone
## SPDX-License-Identifier: AGPL-3.0-or-later
## Please see the LICENSE file for details.
## WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
##------------------------------------------------------------------------------

from __future__ import annotations

from flask import Flask, jsonify, redirect, render_template_string, request, url_for

from .waveform_viewer import WaveformViewerApp, OpcodeNames


OPCODE_OPTIONS = [
    {"value": value, "label": label}
    for value, label in sorted(OpcodeNames.items(), key=lambda item: item[0])
]


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
      --danger: #ff8a8a;
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
    button, .btn-link {
      background: var(--panel2);
      color: var(--text);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 10px 14px;
      cursor: pointer;
      font-weight: 600;
      text-decoration: none;
      display: inline-block;
    }
    button:hover, .btn-link:hover { border-color: var(--accent); }
    .btn-small {
      padding: 7px 10px;
      font-size: 13px;
    }
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
      top: -274px;
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
      vertical-align: top;
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
    .edit-box {
      margin-top: 12px;
      padding: 12px;
      border: 1px solid var(--border);
      border-radius: 12px;
      background: rgba(11, 16, 32, 0.8);
    }
    .edit-box[hidden] {
      display: none !important;
    }
    .edit-row td {
      padding: 0 !important;
      border-bottom: none !important;
    }
    .form-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(180px, 1fr));
      gap: 10px 12px;
      align-items: end;
    }
    .form-grid-4 {
      display: grid;
      grid-template-columns: repeat(4, minmax(110px, 1fr));
      gap: 10px 12px;
      align-items: end;
    }
    label {
      display: grid;
      gap: 6px;
      font-size: 13px;
      color: var(--muted);
    }
    input, select {
      width: 100%;
      border-radius: 10px;
      border: 1px solid var(--border);
      background: #0f1526;
      color: var(--text);
      padding: 9px 10px;
      font-size: 14px;
    }
    .actions-inline {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      margin-top: 12px;
    }
    .mono {
      font-family: Consolas, Monaco, monospace;
    }
    .hint {
      color: var(--muted);
      font-size: 12px;
      line-height: 1.4;
    }
    .row-actions {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      justify-content: flex-end;
    }
    .duel-tables {
    display: flex;
    gap: 16px;
    align-items: flex-start;
    flex-wrap: wrap;
    }
    .duel-tables table {
    flex: 1;
    min-width: 280px;
    }
    @media (max-width: 1300px) {
      .layout { grid-template-columns: 1fr; }
    }
    @media (max-width: 900px) {
      .form-grid, .form-grid-4 { grid-template-columns: 1fr; }
    }
  </style>
  <script>
    function toggleEdit(id) {
      const elem = document.getElementById(id);
      if (!elem) return;
      elem.hidden = !elem.hidden;
    }

    function updateOperandField(selectElem, operandWrapId, currentValues) {
      const opcode = parseInt(selectElem.value || "0", 10);
      const wrap = document.getElementById(operandWrapId);
      if (!wrap) return;

      let html = "";
      let operandHint = "Enter decimal like 64 or hex like 0x40.";

      if (opcode === 10) {
        const loopRepeatCount = currentValues.loop_repeat_count || "0";
        const loopTargetIdx = currentValues.loop_target_idx || "0";
        operandHint = "LOOP operand format: operand[19:8] = loop_repeat_count, operand[7:0] = loop_target_idx.";
        html = `
          <div class="form-grid">
            <label>
              loop_repeat_count
              <input name="loop_repeat_count" value="${loopRepeatCount}" placeholder="decimal or 0x...">
            </label>
            <label>
              loop_target_idx
              <input name="loop_target_idx" value="${loopTargetIdx}" placeholder="decimal or 0x...">
            </label>
          </div>
          <div class="hint">${operandHint}</div>
        `;
      } else {
        let operandLabel = "operand";

        if (opcode === 1) {
          operandLabel = "operand";
          operandHint = "PLAY operand. Enter decimal like 64 or hex like 0x40.";
        } else if (opcode === 2) {
          operandLabel = "operand";
          operandHint = "MEASURE operand. Enter decimal like 64 or hex like 0x40.";
        } else if (opcode === 3) {
          operandLabel = "wait_cycles";
          operandHint = "WAIT operand. Enter decimal like 64 or hex like 0x40.";
        } else if (opcode === 5) {
          operandLabel = "jump_addr";
          operandHint = "JUMP operand. Enter decimal like 10 or hex like 0xA.";
        } else if (opcode === 6) {
          operandLabel = "wait_cycles";
          operandHint = "WAIT_RESET operand. Enter decimal like 64 or hex like 0x40.";
        } else if (opcode === 7) {
          operandLabel = "operand";
          operandHint = "ACCUM_CLEAR usually uses 0, but decimal and 0x input are both accepted.";
        } else if (opcode === 8) {
          operandLabel = "operand";
          operandHint = "ACCUM operand. Enter decimal like 64 or hex like 0x40.";
        } else if (opcode === 9) {
          operandLabel = "operand";
          operandHint = "ACCUM_AVG operand. Enter decimal like 64 or hex like 0x40.";
        } else if (opcode === 0 || opcode === 4) {
          operandLabel = "operand";
          operandHint = "Usually 0 for NOP and END. Decimal and 0x input are both accepted.";
        }

        const operandValue = currentValues.operand || "0";
        html = `
          <label>
            ${operandLabel}
            <input name="operand" value="${operandValue}" placeholder="decimal or 0x...">
          </label>
          <div class="hint">${operandHint}</div>
        `;
      }

      wrap.innerHTML = html;
    }

    function initInstructionEditors() {
      document.querySelectorAll("[data-instr-editor='1']").forEach((container) => {
        const selectElem = container.querySelector("select[data-role='opcode']");
        const wrap = container.querySelector("[data-role='operand-wrap']");
        if (!selectElem || !wrap) return;
        const operandWrapId = wrap.id;

        const currentValues = {
          operand: wrap.getAttribute("data-current-operand"),
          loop_repeat_count: wrap.getAttribute("data-current-loop-repeat-count"),
          loop_target_idx: wrap.getAttribute("data-current-loop-target-idx"),
        };

        updateOperandField(selectElem, operandWrapId, currentValues);
        selectElem.addEventListener("change", function () {
          const operandInput = document.querySelector("#" + operandWrapId + " input[name='operand']");
          const loopRepeatInput = document.querySelector("#" + operandWrapId + " input[name='loop_repeat_count']");
          const loopTargetInput = document.querySelector("#" + operandWrapId + " input[name='loop_target_idx']");

          if (operandInput) {
            currentValues.operand = operandInput.value;
          }
          if (loopRepeatInput) {
            currentValues.loop_repeat_count = loopRepeatInput.value;
          }
          if (loopTargetInput) {
            currentValues.loop_target_idx = loopTargetInput.value;
          }

          updateOperandField(selectElem, operandWrapId, currentValues);
        });
      });
    }

    document.addEventListener("DOMContentLoaded", initInstructionEditors);
  </script>
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
        <input type="hidden" name="action" value="refresh_data">
        <button type="submit">Refresh Data</button>
      </form>
      <form method="post" action="{{ url_for('action_route') }}">
        <input type="hidden" name="action" value="send_all">
        <button type="submit">Send all registers</button>
      </form>
      <button type="button" onclick="toggleEdit('json-file-box')">Save or load JSON</button>
      <form method="post" action="{{ url_for('action_route') }}">
        <input type="hidden" name="action" value="start_exp">
        <button type="submit">Start experiment</button>
      </form>
      <form method="post" action="{{ url_for('action_route') }}">
        <input type="hidden" name="action" value="soft_reset">
        <button type="submit" disabled title="Soft reset is disabled for now">Soft reset</button>
      </form>
    </div>
  </div>

  <div class="panel edit-box" id="json-file-box" hidden style="margin-bottom: 18px;">
    <h2 style="margin-top:0;">JSON Config File</h2>
    <div class="hint" style="margin-bottom:10px;">Save the current local writable configuration to a JSON file, or load a JSON file into the local shadow and send it to the FPGA.</div>
    <div class="actions-inline">
      <form method="post" action="{{ url_for('save_json_config_route') }}">
        <div class="form-grid" style="min-width: 420px;">
          <label>
            Save file path
            <input name="json_path" value="{{ state.json_default_path }}" placeholder="qubit_fpga_config.json">
          </label>
        </div>
        <div class="actions-inline">
          <button type="submit">Save JSON file</button>
        </div>
      </form>
      <form method="post" action="{{ url_for('load_json_config_route') }}">
        <div class="form-grid" style="min-width: 420px;">
          <label>
            Load file path
            <input name="json_path" value="{{ state.json_default_path }}" placeholder="qubit_fpga_config.json">
          </label>
        </div>
        <div class="actions-inline">
          <button type="submit">Load JSON file and send</button>
        </div>
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
            <div class="row-actions">
              <button type="button" class="btn-small" onclick="toggleEdit('edit-playcfg-{{ cfg.index }}')">Edit</button>
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

          <div class="edit-box" id="edit-playcfg-{{ cfg.index }}" hidden>
            <form method="post" action="{{ url_for('edit_play_cfg_route', index=cfg.index) }}">
              <div class="form-grid">
                <label>
                  amp_q8_8
                  <input name="amp_q8_8" value="{{ cfg.edit.amp_q8_8 }}" placeholder="0.5 or 0x0080">
                </label>
                <label>
                  phase_q8_8
                  <input name="phase_q8_8" value="{{ cfg.edit.phase_q8_8 }}" placeholder="0.5 or 0x0080">
                </label>
                <label>
                  duration_ns
                  <input name="duration_ns" value="{{ cfg.edit.duration_ns }}" placeholder="decimal or 0x...">
                </label>
                <label>
                  sigma_ns
                  <input name="sigma_ns" value="{{ cfg.edit.sigma_ns }}" placeholder="decimal or 0x...">
                </label>
                <label>
                  pad_ns
                  <input name="pad_ns" value="{{ cfg.edit.pad_ns }}" placeholder="decimal or 0x...">
                </label>
                <label>
                  detune_hz
                  <input name="detune_hz" value="{{ cfg.edit.detune_hz }}" placeholder="decimal or 0x...">
                </label>
                <label>
                  envelope
                  <select name="envelope">
                    <option value="SQUARE" {% if cfg.edit.envelope == 'SQUARE' %}selected{% endif %}>SQUARE</option>
                    <option value="GAUSS" {% if cfg.edit.envelope == 'GAUSS' %}selected{% endif %}>GAUSS</option>
                  </select>
                </label>
              </div>
              <div class="actions-inline">
                <button type="submit">Save and Send</button>
                <button type="button" onclick="toggleEdit('edit-playcfg-{{ cfg.index }}')">Cancel</button>
              </div>
              <div class="hint">Q8.8 fields accept decimal integer, float like 0.5, or hex like 0x0080.</div>
            </form>
          </div>
        </div>
        {% endfor %}
      </div>
    </div>

    <div style="display:grid; gap: 18px; align-content:start;">
    
      <div class="panel">
        <h2 style="margin-top:0;">Status</h2>
        <div class="duel-tables">
            <table>
            <tbody>
                <tr><td>reset_wait_cycles</td><td>{{ state.control.reset_wait_cycles }}</td></tr>
            </tbody>
            </table>
            <table>
            <tbody>
                <tr><td>captured_packets</td><td>{{ state.control.captured_packets }}</td></tr>
            </tbody>
            </table>
        </div>
      </div>
      
      <div class="panel">
        <h2 style="margin-top:0;">Calibration Registers</h2>
        <div class="duel-tables">
            <table>
            <tbody>
                <tr><th>Field</th><th>Raw</th><th>Value</th></tr>
                {% for row in state.calibration_rows.left %}
                <tr><td>{{ row.field }}</td><td>{{ row.raw }}</td><td>{{ row.value }}</td></tr>
                {% endfor %}
            </tbody>
            </table>
            <table>
            <tbody>
                <tr><th>Field</th><th>Raw</th><th>Value</th></tr>
                {% for row in state.calibration_rows.right %}
                <tr><td>{{ row.field }}</td><td>{{ row.raw }}</td><td>{{ row.value }}</td></tr>
                {% endfor %}
            </tbody>
            </table>
        </div>
        <div class="hint" style="margin-top:10px;">Calibration registers are view only in this UI.</div>
      </div>    

      <div class="panel">
        <div class="card-head" style="margin-bottom:0;">
          <h2 style="margin:0;">Experiment Results</h2>
          <button type="button" class="section-toggle" onclick="toggleSection('experiment-results-body', this)">Hide</button>
        </div>
        <div id="experiment-results-body">
          <div class="hint" style="margin-top:10px;">Captured readout results are cleared when Start experiment is clicked.</div>

          <table style="margin-top:10px;">
            <tbody>
              <tr><td>captured_results</td><td>{{ state.experiment_results.count }}</td></tr>
            </tbody>
          </table>

          {% if state.experiment_results.count == 0 %}
          <div class="note" style="margin-top:12px;">
            No experiment results captured yet. Click Start experiment to begin collecting FPGA readout results.
          </div>
          {% else %}
          <div class="plot-stack">
            <div>
              <div style="margin-bottom: 6px; color: var(--muted);">I_avg vs index of captured results</div>
              <img src="{{ state.experiment_results.plots.i_avg }}" alt="I_avg experiment results plot">
            </div>
            <div>
              <div style="margin-bottom: 6px; color: var(--muted);">Q_avg vs index of captured results</div>
              <img src="{{ state.experiment_results.plots.q_avg }}" alt="Q_avg experiment results plot">
            </div>
            <div>
              <div style="margin-bottom: 6px; color: var(--muted);">meas_state vs index of captured results</div>
              <img src="{{ state.experiment_results.plots.meas_state }}" alt="meas_state experiment results plot">
            </div>
          </div>

          <div class="results-table">
            <table>
              <thead>
                <tr><th>Idx</th><th>I_avg_q2_14</th><th>Q_avg_q2_14</th><th>I_avg</th><th>Q_avg</th><th>meas_state</th></tr>
              </thead>
              <tbody>
                {% for row in state.experiment_results.rows %}
                <tr>
                  <td>{{ row.index }}</td>
                  <td>{{ row.I_avg_q2_14 }}</td>
                  <td>{{ row.Q_avg_q2_14 }}</td>
                  <td>{{ '%.6f'|format(row.I_avg) }}</td>
                  <td>{{ '%.6f'|format(row.Q_avg) }}</td>
                  <td>{{ row.meas_state }}</td>
                </tr>
                {% endfor %}
              </tbody>
            </table>
          </div>
          {% endif %}
        </div>
      </div>

      <div class="panel">
        <h2 style="margin-top:0;">Measure Config Registers</h2>
        <table>
          <thead>
            <tr><th>Idx</th><th>n_readout</th><th>readout_ns</th><th>ringup_ns</th><th></th></tr>
          </thead>
          <tbody>
            {% for cfg in state.measure_cfgs %}
            <tr id="measurecfg-{{ cfg.index }}">
              <td>{{ cfg.index }}</td>
              <td>{{ cfg.n_readout }}</td>
              <td>{{ cfg.readout_ns }}</td>
              <td>{{ cfg.ringup_ns }}</td>
              <td><button type="button" class="btn-small" onclick="toggleEdit('edit-measurecfg-{{ cfg.index }}')">Edit</button></td>
            </tr>
            <tr class="edit-row">
              <td colspan="5" style="padding-top:0;">
                <div class="edit-box" id="edit-measurecfg-{{ cfg.index }}" hidden>
                  <form method="post" action="{{ url_for('edit_measure_cfg_route', index=cfg.index) }}">
                    <div class="form-grid">
                      <label>
                        n_readout
                        <input name="n_readout" value="{{ cfg.edit.n_readout }}" placeholder="decimal or 0x...">
                      </label>
                      <label>
                        readout_ns
                        <input name="readout_ns" value="{{ cfg.edit.readout_ns }}" placeholder="decimal or 0x...">
                      </label>
                      <label>
                        ringup_ns
                        <input name="ringup_ns" value="{{ cfg.edit.ringup_ns }}" placeholder="decimal or 0x...">
                      </label>
                    </div>
                    <div class="actions-inline">
                      <button type="submit">Save and Send</button>
                      <button type="button" onclick="toggleEdit('edit-measurecfg-{{ cfg.index }}')">Cancel</button>
                    </div>
                  </form>
                </div>
              </td>
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
            <tr><th>Idx</th><th>Word</th><th>Opcode</th><th>Flags</th><th>Cfg</th><th>Operand</th><th></th></tr>
          </thead>
          <tbody>
            {% for instr in state.instructions %}
            <tr id="instr-{{ instr.index }}">
              <td>{{ instr.index }}</td>
              <td class="mono">{{ instr.word_hex }}</td>
              <td>{{ instr.opcode_name }}</td>
              <td>{{ instr.flags }}</td>
              <td>{{ instr.cfg }}</td>
              <td>{{ instr.operand }}</td>
              <td><button type="button" class="btn-small" onclick="toggleEdit('edit-instr-{{ instr.index }}')">Edit</button></td>
            </tr>
            <tr class="edit-row">
              <td colspan="7" style="padding-top:0;">
                <div class="edit-box" id="edit-instr-{{ instr.index }}" hidden data-instr-editor="1">
                  <form method="post" action="{{ url_for('edit_instruction_route', index=instr.index) }}">
                    <div class="form-grid-4">
                      <label>
                        word
                        <input value="{{ instr.word_hex }}" disabled>
                      </label>
                      <label>
                        opcode
                        <select name="opcode" data-role="opcode">
                          {% for opt in state.opcode_options %}
                          <option value="{{ opt.value }}" {% if opt.value == instr.edit.opcode %}selected{% endif %}>{{ opt.label }}</option>
                          {% endfor %}
                        </select>
                      </label>
                      <label>
                        flags
                        <input name="flags" value="{{ instr.edit.flags }}" placeholder="0..15">
                      </label>
                      <label>
                        cfg
                        <input name="cfg" value="{{ instr.edit.cfg }}" placeholder="0..15">
                      </label>
                    </div>
                    <div class="form-grid" style="margin-top:10px;">
                      <div id="operand-wrap-{{ instr.index }}"
                           data-role="operand-wrap"
                           data-current-operand="{{ instr.edit.operand }}"
                           data-current-loop-repeat-count="{{ instr.edit.loop_repeat_count }}"
                           data-current-loop-target-idx="{{ instr.edit.loop_target_idx }}">
                      </div>
                    </div>
                    <div class="actions-inline">
                      <button type="submit">Save and Send</button>
                      <button type="button" onclick="toggleEdit('edit-instr-{{ instr.index }}')">Cancel</button>
                    </div>
                    <div class="hint">Operand accepts decimal like 64 or hex like 0x40.</div>
                  </form>
                </div>
              </td>
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


def _parse_int_like(value, default: int = 0) -> int:
    if value is None:
        return int(default)

    if isinstance(value, bool):
        return int(value)

    if isinstance(value, int):
        return int(value)

    if isinstance(value, float):
        return int(value)

    s = str(value).strip()
    if not s:
        return int(default)

    s = s.replace(" ", "").replace("_", "")
    if s.lower().startswith("0x"):
        return int(s, 16)
    return int(s, 10)


def _parse_q8_8_like(value, default: int = 0) -> int:
    if value is None:
        return int(default)

    s = str(value).strip()
    if not s:
        return int(default)

    s = s.replace(" ", "").replace("_", "")
    if s.lower().startswith("0x"):
        return int(s, 16)
    if "." in s:
        return int(round(float(s) * 256.0))
    return int(s, 10)


def _hex_u16(x: int) -> str:
    return f"0x{int(x) & 0xFFFF:04X}"


def _hex_u32(x: int) -> str:
    return f"0x{int(x) & 0xFFFFFFFF:08X}"


def _q2_14_to_float(value: int) -> float:
    return float(int(value)) / 16384.0


def _format_calibration_value(field: str, raw_value: int) -> str:
    raw_value = int(raw_value)
    if field == "cal_sample_count":
        return f"{raw_value} samples"
    if field in (
        "cal_i_avg",
        "cal_q_avg",
        "cal_i0_ref",
        "cal_q0_ref",
        "cal_i1_ref",
        "cal_q1_ref",
        "cal_i_threshold",
    ):
        return f"{_q2_14_to_float(raw_value):.6f} FS (Q2.14)"
    if field == "cal_state_polarity":
        return "1 = positive state" if raw_value else "0 = negative state"
    if field in ("cal_i0q0_valid", "cal_i1q1_valid", "cal_threshold_valid", "meas_state_valid"):
        return "valid" if raw_value else "not valid"
    if field == "meas_state":
        return "state 1" if raw_value else "state 0"
    return str(raw_value)


def _build_calibration_rows(calibration: dict) -> dict:
    left_fields = [
        "cal_i_threshold",
        "cal_state_polarity",
        "cal_i0q0_valid",
        "cal_i1q1_valid",
        "cal_threshold_valid",
        "meas_state",
        "meas_state_valid",
    ]
    right_fields = [
        "cal_sample_count",
        "cal_i_avg",
        "cal_q_avg",
        "cal_i0_ref",
        "cal_q0_ref",
        "cal_i1_ref",
        "cal_q1_ref",
    ]

    def _rows(fields):
        rows = []
        for field in fields:
            raw_value = int(calibration.get(field, 0))
            rows.append({
                "field": field,
                "raw": raw_value,
                "value": _format_calibration_value(field, raw_value),
            })
        return rows

    return {
        "left": _rows(left_fields),
        "right": _rows(right_fields),
    }


def _decode_instr_word(word: int) -> dict:
    word = int(word) & 0xFFFFFFFF
    opcode = (word >> 28) & 0xF
    flags = (word >> 24) & 0xF
    cfg = (word >> 20) & 0xF
    operand = word & 0xFFFFF
    return {
        "opcode": opcode,
        "flags": flags,
        "cfg": cfg,
        "operand": operand,
        "loop_repeat_count": (operand >> 8) & 0xFFF,
        "loop_target_idx": operand & 0xFF,
        "opcode_name": OpcodeNames.get(opcode, f"OP_{opcode:X}"),
    }


class WebUiApp:
    def __init__(self, host: str = '127.0.0.1', port: int = 5000, fs_hz: float = 1.0e9, if_hz: float = 50.0e6):
        self.host = host
        self.port = int(port)
        self.viewer = WaveformViewerApp(fs_hz=fs_hz, if_hz=if_hz)
        self.app = Flask(__name__)
        self._menu = None
        self._register_routes()

    def _build_page_state(self):
        state = self.viewer.get_state_snapshot()
        state["opcode_options"] = OPCODE_OPTIONS
        state["calibration_rows"] = _build_calibration_rows(state.get("calibration", {}))
        state["json_default_path"] = "qubit_fpga_config.json"

        if self._menu is None:
            return state

        shadow = self._menu.shadow

        play_cfgs = state.get("play_cfgs", [])
        for idx, cfg in enumerate(play_cfgs):
            if idx < len(shadow.play_cfgs):
                raw = shadow.play_cfgs[idx]
                cfg["edit"] = {
                    "amp_q8_8": _hex_u16(raw.amp_q8_8),
                    "phase_q8_8": _hex_u16(raw.phase_q8_8),
                    "duration_ns": str(int(raw.duration_ns)),
                    "sigma_ns": str(int(raw.sigma_ns)),
                    "pad_ns": str(int(raw.pad_ns)),
                    "detune_hz": str(int(raw.detune_hz)),
                    "envelope": str(raw.envelope).strip().upper(),
                }

        measure_cfgs = state.get("measure_cfgs", [])
        for idx, cfg in enumerate(measure_cfgs):
            if idx < len(shadow.measure_cfgs):
                raw = shadow.measure_cfgs[idx]
                cfg["edit"] = {
                    "n_readout": str(int(raw.n_readout)),
                    "readout_ns": str(int(raw.readout_ns)),
                    "ringup_ns": str(int(raw.ringup_ns)),
                }

        instructions = state.get("instructions", [])
        for idx, instr in enumerate(instructions):
            if idx < len(shadow.instr_words):
                dec = _decode_instr_word(shadow.instr_words[idx])
                instr["edit"] = {
                    "opcode": dec["opcode"],
                    "flags": dec["flags"],
                    "cfg": dec["cfg"],
                    "operand": str(dec["operand"]),
                    "loop_repeat_count": str(dec["loop_repeat_count"]),
                    "loop_target_idx": str(dec["loop_target_idx"]),
                }

        return state

    def _register_routes(self) -> None:
        @self.app.get('/')
        def index():
            return render_template_string(PAGE_HTML, state=self._build_page_state())

        @self.app.get('/api/state')
        def api_state():
            return jsonify(self._build_page_state())

        @self.app.post('/action')
        def action_route():
            action = str(request.form.get('action', '')).strip().lower()
            if action == 'refresh_data':
                self.viewer.request_register_dump()
            elif action == 'send_all':
                self.viewer.send_all_registers()
            elif action == 'start_exp':
                self.viewer.send_start_experiment()
            elif action == 'soft_reset':
                self.viewer.send_soft_reset()
            return redirect(url_for('index'))

        @self.app.post('/edit/play_cfg/<int:index>')
        def edit_play_cfg_route(index: int):
            if self._menu is None:
                return redirect(url_for('index'))

            if index < 0 or index >= len(self._menu.shadow.play_cfgs):
                return redirect(url_for('index'))

            cfg = self._menu.shadow.play_cfgs[index]
            cfg.amp_q8_8 = _parse_q8_8_like(request.form.get("amp_q8_8"), cfg.amp_q8_8)
            cfg.phase_q8_8 = _parse_q8_8_like(request.form.get("phase_q8_8"), cfg.phase_q8_8)
            cfg.duration_ns = _parse_int_like(request.form.get("duration_ns"), cfg.duration_ns)
            cfg.sigma_ns = _parse_int_like(request.form.get("sigma_ns"), cfg.sigma_ns)
            cfg.pad_ns = _parse_int_like(request.form.get("pad_ns"), cfg.pad_ns)
            cfg.detune_hz = _parse_int_like(request.form.get("detune_hz"), cfg.detune_hz)
            cfg.envelope = str(request.form.get("envelope", cfg.envelope)).strip().upper() or cfg.envelope

            self._menu.send_play_cfg(index)
            self.viewer.load_from_shadow(self._menu)
            return redirect(url_for('index', _anchor=f'playcfg-{index}'))

        @self.app.post('/edit/measure_cfg/<int:index>')
        def edit_measure_cfg_route(index: int):
            if self._menu is None:
                return redirect(url_for('index'))

            if index < 0 or index >= len(self._menu.shadow.measure_cfgs):
                return redirect(url_for('index'))

            cfg = self._menu.shadow.measure_cfgs[index]
            cfg.n_readout = _parse_int_like(request.form.get("n_readout"), cfg.n_readout)
            cfg.readout_ns = _parse_int_like(request.form.get("readout_ns"), cfg.readout_ns)
            cfg.ringup_ns = _parse_int_like(request.form.get("ringup_ns"), cfg.ringup_ns)

            self._menu.send_measure_cfg(index)
            self.viewer.load_from_shadow(self._menu)
            return redirect(url_for('index', _anchor=f'measurecfg-{index}'))

        @self.app.post('/edit/instruction/<int:index>')
        def edit_instruction_route(index: int):
            if self._menu is None:
                return redirect(url_for('index'))

            if index < 0 or index >= len(self._menu.shadow.instr_words):
                return redirect(url_for('index'))

            opcode = _parse_int_like(request.form.get("opcode"), 0) & 0xF
            flags = _parse_int_like(request.form.get("flags"), 0) & 0xF
            cfg = _parse_int_like(request.form.get("cfg"), 0) & 0xF

            if opcode == 0xA:
                loop_repeat_count = _parse_int_like(request.form.get("loop_repeat_count"), 0) & 0xFFF
                loop_target_idx = _parse_int_like(request.form.get("loop_target_idx"), 0) & 0xFF
                operand = ((loop_repeat_count & 0xFFF) << 8) | (loop_target_idx & 0xFF)
            else:
                operand = _parse_int_like(request.form.get("operand"), 0) & 0xFFFFF

            word = (opcode << 28) | (flags << 24) | (cfg << 20) | operand
            self._menu.shadow.instr_words[index] = word

            self._menu.send_instr(index)
            self.viewer.load_from_shadow(self._menu)
            return redirect(url_for('index', _anchor=f'instr-{index}'))

        @self.app.post('/json/save')
        def save_json_config_route():
            if self._menu is not None:
                json_path = str(request.form.get('json_path', 'qubit_fpga_config.json')).strip() or 'qubit_fpga_config.json'
                self._menu.save_json_config_file(json_path)
                self.viewer.load_from_shadow(self._menu)
            return redirect(url_for('index'))

        @self.app.post('/json/load')
        def load_json_config_route():
            if self._menu is not None:
                json_path = str(request.form.get('json_path', 'qubit_fpga_config.json')).strip() or 'qubit_fpga_config.json'
                self._menu.load_json_config_file(json_path, send_to_fpga=True)
                self.viewer.load_from_shadow(self._menu)
            return redirect(url_for('index'))

        self.save_json_config_route = save_json_config_route
        self.load_json_config_route = load_json_config_route
        self.action_route = action_route
        self.edit_play_cfg_route = edit_play_cfg_route
        self.edit_measure_cfg_route = edit_measure_cfg_route
        self.edit_instruction_route = edit_instruction_route

    def attach_menu(self, menu) -> None:
        self._menu = menu
        self.viewer.attach_menu(menu)

    def load_from_shadow(self, menu) -> None:
        self._menu = menu
        self.viewer.load_from_shadow(menu)

    def post_packet(self, label: str, packet: bytes) -> None:
        self.viewer.post_packet(label, packet)

    def clear_experiment_results(self) -> None:
        self.viewer.clear_experiment_results()

    def capture_measure_result(
        self,
        *,
        i_avg_q2_14: int,
        q_avg_q2_14: int,
        i_avg: float,
        q_avg: float,
        meas_state: int,
    ) -> None:
        self.viewer.capture_measure_result(
            i_avg_q2_14=i_avg_q2_14,
            q_avg_q2_14=q_avg_q2_14,
            i_avg=i_avg,
            q_avg=q_avg,
            meas_state=meas_state,
        )

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
