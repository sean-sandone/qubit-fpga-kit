//------------------------------------------------------------------------------
// PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
//------------------------------------------------------------------------------
// AUTHORS: Sean Sandone
// WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
//------------------------------------------------------------------------------

module cmd_formatter (
    input  logic clk,
    input  logic rst_sync_n,

    input  logic                  start,
    input  logic                  is_play,
    input  logic                  is_reset,
    input  logic [3:0]            cfg_index,
    input  rtl_pkg::play_cfg_t    play_cfg,
    input  rtl_pkg::measure_cfg_t measure_cfg,

    output logic [7:0] tx_data,
    output logic       tx_valid,
    input  logic       tx_ready,

    output logic busy,
    output logic done_pulse
);

    import rtl_pkg::*;

    typedef enum logic [1:0] {
        FmtStateIdle = 2'd0,
        FmtStateSend = 2'd1,
        FmtStateDone = 2'd2
    } fmt_state_t;

    fmt_state_t state_r;

    logic         is_play_r;
    logic         is_reset_r;
    logic [3:0]   cfg_index_r;
    play_cfg_t    play_cfg_r;
    measure_cfg_t measure_cfg_r;
    logic [5:0]   seg_r;
    logic [5:0]   char_idx_r;

    function automatic logic [7:0] hex_char(input logic [3:0] nibble);
        case (nibble)
            4'h0: hex_char = "0";
            4'h1: hex_char = "1";
            4'h2: hex_char = "2";
            4'h3: hex_char = "3";
            4'h4: hex_char = "4";
            4'h5: hex_char = "5";
            4'h6: hex_char = "6";
            4'h7: hex_char = "7";
            4'h8: hex_char = "8";
            4'h9: hex_char = "9";
            4'hA: hex_char = "A";
            4'hB: hex_char = "B";
            4'hC: hex_char = "C";
            4'hD: hex_char = "D";
            4'hE: hex_char = "E";
            default: hex_char = "F";
        endcase
    endfunction

    function automatic logic [7:0] hex1_char(input logic [3:0] value, input logic [2:0] idx);
        case (idx)
            3'd0: hex1_char = hex_char(value);
            default: hex1_char = "0";
        endcase
    endfunction

    function automatic logic [7:0] hex4_char(input logic [15:0] value, input logic [2:0] idx);
        case (idx)
            3'd0: hex4_char = hex_char(value[15:12]);
            3'd1: hex4_char = hex_char(value[11:8]);
            3'd2: hex4_char = hex_char(value[7:4]);
            default: hex4_char = hex_char(value[3:0]);
        endcase
    endfunction

    function automatic logic [7:0] hex8_char(input logic [31:0] value, input logic [3:0] idx);
        case (idx)
            4'd0: hex8_char = hex_char(value[31:28]);
            4'd1: hex8_char = hex_char(value[27:24]);
            4'd2: hex8_char = hex_char(value[23:20]);
            4'd3: hex8_char = hex_char(value[19:16]);
            4'd4: hex8_char = hex_char(value[15:12]);
            4'd5: hex8_char = hex_char(value[11:8]);
            4'd6: hex8_char = hex_char(value[7:4]);
            default: hex8_char = hex_char(value[3:0]);
        endcase
    endfunction

    function automatic logic [5:0] env_len(input envelope_t env);
        if (env == ENV_GAUSS) begin
            env_len = 5;
        end else begin
            env_len = 6;
        end
    endfunction

    function automatic logic [7:0] env_char(input envelope_t env, input logic [2:0] idx);
        if (env == ENV_GAUSS) begin
            case (idx)
                3'd0: env_char = "G";
                3'd1: env_char = "A";
                3'd2: env_char = "U";
                3'd3: env_char = "S";
                default: env_char = "S";
            endcase
        end else begin
            case (idx)
                3'd0: env_char = "S";
                3'd1: env_char = "Q";
                3'd2: env_char = "U";
                3'd3: env_char = "A";
                3'd4: env_char = "R";
                default: env_char = "E";
            endcase
        end
    endfunction

    function automatic logic [5:0] play_seg_len(input logic [5:0] seg, input play_cfg_t cfg);
        case (seg)
            6'd0:  play_seg_len = 23; // {"cmd":"PLAY","cfg":"0x
            6'd1:  play_seg_len = 1;  // cfg nibble
            6'd2:  play_seg_len = 16; // ","amp_q8_8":"
            6'd3:  play_seg_len = 4;  // amp_q8_8
            6'd4:  play_seg_len = 18; // ","phase_q8_8":"
            6'd5:  play_seg_len = 4;  // phase_q8_8
            6'd6:  play_seg_len = 17; // ","duration_ns":"
            6'd7:  play_seg_len = 8;  // duration_ns
            6'd8:  play_seg_len = 14; // ","sigma_ns":"
            6'd9:  play_seg_len = 8;  // sigma_ns
            6'd10: play_seg_len = 12; // ","pad_ns":"
            6'd11: play_seg_len = 8;  // pad_ns
            6'd12: play_seg_len = 15; // ","detune_hz":"
            6'd13: play_seg_len = 8;  // detune_hz
            6'd14: play_seg_len = 14; // ","envelope":"
            6'd15: play_seg_len = env_len(cfg.envelope);
            default: play_seg_len = 3; // "}\n
        endcase
    endfunction

    function automatic logic [7:0] play_seg_byte(
        input logic [5:0] seg,
        input logic [5:0] idx,
        input logic [3:0] cfg_index_v,
        input play_cfg_t cfg
    );
        case (seg)
            6'd0: begin
                case (idx)
                    0:  play_seg_byte = "{";
                    1:  play_seg_byte = "\"";
                    2:  play_seg_byte = "c";
                    3:  play_seg_byte = "m";
                    4:  play_seg_byte = "d";
                    5:  play_seg_byte = "\"";
                    6:  play_seg_byte = ":";
                    7:  play_seg_byte = "\"";
                    8:  play_seg_byte = "P";
                    9:  play_seg_byte = "L";
                    10: play_seg_byte = "A";
                    11: play_seg_byte = "Y";
                    12: play_seg_byte = "\"";
                    13: play_seg_byte = ",";
                    14: play_seg_byte = "\"";
                    15: play_seg_byte = "c";
                    16: play_seg_byte = "f";
                    17: play_seg_byte = "g";
                    18: play_seg_byte = "\"";
                    19: play_seg_byte = ":";
                    20: play_seg_byte = "\"";
                    21: play_seg_byte = "0";
                    default: play_seg_byte = "x";
                endcase
            end

            6'd1: begin
                play_seg_byte = hex1_char(cfg_index_v, idx[2:0]);
            end

            6'd2: begin
                case (idx)
                    0:  play_seg_byte = "\"";
                    1:  play_seg_byte = ",";
                    2:  play_seg_byte = "\"";
                    3:  play_seg_byte = "a";
                    4:  play_seg_byte = "m";
                    5:  play_seg_byte = "p";
                    6:  play_seg_byte = "_";
                    7:  play_seg_byte = "q";
                    8:  play_seg_byte = "8";
                    9:  play_seg_byte = "_";
                    10: play_seg_byte = "8";
                    11: play_seg_byte = "\"";
                    12: play_seg_byte = ":";
                    13: play_seg_byte = "\"";
                    default: play_seg_byte = " ";
                endcase
            end

            6'd3: begin
                play_seg_byte = hex4_char(cfg.amp_q8_8, idx[2:0]);
            end

            6'd4: begin
                case (idx)
                    0:  play_seg_byte = "\"";
                    1:  play_seg_byte = ",";
                    2:  play_seg_byte = "\"";
                    3:  play_seg_byte = "p";
                    4:  play_seg_byte = "h";
                    5:  play_seg_byte = "a";
                    6:  play_seg_byte = "s";
                    7:  play_seg_byte = "e";
                    8:  play_seg_byte = "_";
                    9:  play_seg_byte = "q";
                    10: play_seg_byte = "8";
                    11: play_seg_byte = "_";
                    12: play_seg_byte = "8";
                    13: play_seg_byte = "\"";
                    14: play_seg_byte = ":";
                    15: play_seg_byte = "\"";
                    default: play_seg_byte = " ";
                endcase
            end

            6'd5: begin
                play_seg_byte = hex4_char(cfg.phase_q8_8, idx[2:0]);
            end

            6'd6: begin
                case (idx)
                    0:  play_seg_byte = "\"";
                    1:  play_seg_byte = ",";
                    2:  play_seg_byte = "\"";
                    3:  play_seg_byte = "d";
                    4:  play_seg_byte = "u";
                    5:  play_seg_byte = "r";
                    6:  play_seg_byte = "a";
                    7:  play_seg_byte = "t";
                    8:  play_seg_byte = "i";
                    9:  play_seg_byte = "o";
                    10: play_seg_byte = "n";
                    11: play_seg_byte = "_";
                    12: play_seg_byte = "n";
                    13: play_seg_byte = "s";
                    14: play_seg_byte = "\"";
                    15: play_seg_byte = ":";
                    default: play_seg_byte = "\"";
                endcase
            end

            6'd7: begin
                play_seg_byte = hex8_char(cfg.duration_ns, idx[3:0]);
            end

            6'd8: begin
                case (idx)
                    0:  play_seg_byte = "\"";
                    1:  play_seg_byte = ",";
                    2:  play_seg_byte = "\"";
                    3:  play_seg_byte = "s";
                    4:  play_seg_byte = "i";
                    5:  play_seg_byte = "g";
                    6:  play_seg_byte = "m";
                    7:  play_seg_byte = "a";
                    8:  play_seg_byte = "_";
                    9:  play_seg_byte = "n";
                    10: play_seg_byte = "s";
                    11: play_seg_byte = "\"";
                    12: play_seg_byte = ":";
                    default: play_seg_byte = "\"";
                endcase
            end

            6'd9: begin
                play_seg_byte = hex8_char(cfg.sigma_ns, idx[3:0]);
            end

            6'd10: begin
                case (idx)
                    0:  play_seg_byte = "\"";
                    1:  play_seg_byte = ",";
                    2:  play_seg_byte = "\"";
                    3:  play_seg_byte = "p";
                    4:  play_seg_byte = "a";
                    5:  play_seg_byte = "d";
                    6:  play_seg_byte = "_";
                    7:  play_seg_byte = "n";
                    8:  play_seg_byte = "s";
                    9:  play_seg_byte = "\"";
                    10: play_seg_byte = ":";
                    default: play_seg_byte = "\"";
                endcase
            end

            6'd11: begin
                play_seg_byte = hex8_char(cfg.pad_ns, idx[3:0]);
            end

            6'd12: begin
                case (idx)
                    0:  play_seg_byte = "\"";
                    1:  play_seg_byte = ",";
                    2:  play_seg_byte = "\"";
                    3:  play_seg_byte = "d";
                    4:  play_seg_byte = "e";
                    5:  play_seg_byte = "t";
                    6:  play_seg_byte = "u";
                    7:  play_seg_byte = "n";
                    8:  play_seg_byte = "e";
                    9:  play_seg_byte = "_";
                    10: play_seg_byte = "h";
                    11: play_seg_byte = "z";
                    12: play_seg_byte = "\"";
                    13: play_seg_byte = ":";
                    default: play_seg_byte = "\"";
                endcase
            end

            6'd13: begin
                play_seg_byte = hex8_char(cfg.detune_hz, idx[3:0]);
            end

            6'd14: begin
                case (idx)
                    0:  play_seg_byte = "\"";
                    1:  play_seg_byte = ",";
                    2:  play_seg_byte = "\"";
                    3:  play_seg_byte = "e";
                    4:  play_seg_byte = "n";
                    5:  play_seg_byte = "v";
                    6:  play_seg_byte = "e";
                    7:  play_seg_byte = "l";
                    8:  play_seg_byte = "o";
                    9:  play_seg_byte = "p";
                    10: play_seg_byte = "e";
                    11: play_seg_byte = "\"";
                    12: play_seg_byte = ":";
                    13: play_seg_byte = "\"";
                    default: play_seg_byte = " ";
                endcase
            end

            6'd15: begin
                play_seg_byte = env_char(cfg.envelope, idx[2:0]);
            end

            default: begin
                case (idx)
                    0: play_seg_byte = "\"";
                    1: play_seg_byte = "}";
                    default: play_seg_byte = 8'h0A;
                endcase
            end
        endcase
    endfunction

    function automatic logic [5:0] meas_seg_len(input logic [5:0] seg);
        case (seg)
            6'd0:  meas_seg_len = 26; // {"cmd":"MEASURE","cfg":"0x
            6'd1:  meas_seg_len = 1;  // cfg nibble
            6'd2:  meas_seg_len = 16; // ","n_readout":"
            6'd3:  meas_seg_len = 4;  // n_readout
            6'd4:  meas_seg_len = 17; // ","readout_ns":"
            6'd5:  meas_seg_len = 8;  // readout_ns
            6'd6:  meas_seg_len = 16; // ","ringup_ns":"
            6'd7:  meas_seg_len = 8;  // ringup_ns
            default: meas_seg_len = 3; // "}\n
        endcase
    endfunction

    function automatic logic [7:0] meas_seg_byte(
        input logic [5:0] seg,
        input logic [5:0] idx,
        input logic [3:0] cfg_index_v,
        input measure_cfg_t cfg
    );
        case (seg)
            6'd0: begin
                case (idx)
                    0:  meas_seg_byte = "{";
                    1:  meas_seg_byte = "\"";
                    2:  meas_seg_byte = "c";
                    3:  meas_seg_byte = "m";
                    4:  meas_seg_byte = "d";
                    5:  meas_seg_byte = "\"";
                    6:  meas_seg_byte = ":";
                    7:  meas_seg_byte = "\"";
                    8:  meas_seg_byte = "M";
                    9:  meas_seg_byte = "E";
                    10: meas_seg_byte = "A";
                    11: meas_seg_byte = "S";
                    12: meas_seg_byte = "U";
                    13: meas_seg_byte = "R";
                    14: meas_seg_byte = "E";
                    15: meas_seg_byte = "\"";
                    16: meas_seg_byte = ",";
                    17: meas_seg_byte = "\"";
                    18: meas_seg_byte = "c";
                    19: meas_seg_byte = "f";
                    20: meas_seg_byte = "g";
                    21: meas_seg_byte = "\"";
                    22: meas_seg_byte = ":";
                    23: meas_seg_byte = "\"";
                    24: meas_seg_byte = "0";
                    default: meas_seg_byte = "x";
                endcase
            end

            6'd1: begin
                meas_seg_byte = hex1_char(cfg_index_v, idx[2:0]);
            end

            6'd2: begin
                case (idx)
                    0:  meas_seg_byte = "\"";
                    1:  meas_seg_byte = ",";
                    2:  meas_seg_byte = "\"";
                    3:  meas_seg_byte = "n";
                    4:  meas_seg_byte = "_";
                    5:  meas_seg_byte = "r";
                    6:  meas_seg_byte = "e";
                    7:  meas_seg_byte = "a";
                    8:  meas_seg_byte = "d";
                    9:  meas_seg_byte = "o";
                    10: meas_seg_byte = "u";
                    11: meas_seg_byte = "t";
                    12: meas_seg_byte = "\"";
                    13: meas_seg_byte = ":";
                    14: meas_seg_byte = "\"";
                    default: meas_seg_byte = " ";
                endcase
            end

            6'd3: begin
                meas_seg_byte = hex4_char(cfg.n_readout, idx[2:0]);
            end

            6'd4: begin
                case (idx)
                    0:  meas_seg_byte = "\"";
                    1:  meas_seg_byte = ",";
                    2:  meas_seg_byte = "\"";
                    3:  meas_seg_byte = "r";
                    4:  meas_seg_byte = "e";
                    5:  meas_seg_byte = "a";
                    6:  meas_seg_byte = "d";
                    7:  meas_seg_byte = "o";
                    8:  meas_seg_byte = "u";
                    9:  meas_seg_byte = "t";
                    10: meas_seg_byte = "_";
                    11: meas_seg_byte = "n";
                    12: meas_seg_byte = "s";
                    13: meas_seg_byte = "\"";
                    14: meas_seg_byte = ":";
                    15: meas_seg_byte = "\"";
                    default: meas_seg_byte = " ";
                endcase
            end

            6'd5: begin
                meas_seg_byte = hex8_char(cfg.readout_ns, idx[3:0]);
            end

            6'd6: begin
                case (idx)
                    0:  meas_seg_byte = "\"";
                    1:  meas_seg_byte = ",";
                    2:  meas_seg_byte = "\"";
                    3:  meas_seg_byte = "r";
                    4:  meas_seg_byte = "i";
                    5:  meas_seg_byte = "n";
                    6:  meas_seg_byte = "g";
                    7:  meas_seg_byte = "u";
                    8:  meas_seg_byte = "p";
                    9:  meas_seg_byte = "_";
                    10: meas_seg_byte = "n";
                    11: meas_seg_byte = "s";
                    12: meas_seg_byte = "\"";
                    13: meas_seg_byte = ":";
                    14: meas_seg_byte = "\"";
                    default: meas_seg_byte = " ";
                endcase
            end

            6'd7: begin
                meas_seg_byte = hex8_char(cfg.ringup_ns, idx[3:0]);
            end

            default: begin
                case (idx)
                    0: meas_seg_byte = "\"";
                    1: meas_seg_byte = "}";
                    default: meas_seg_byte = 8'h0A;
                endcase
            end
        endcase
    endfunction

    function automatic logic [5:0] reset_seg_len(input logic [5:0] seg);
        case (seg)
            default: reset_seg_len = 6'd16; // {"cmd":"RESET"}\n
        endcase
    endfunction

    function automatic logic [7:0] reset_seg_byte(
        input logic [5:0] seg,
        input logic [5:0] idx
    );
        case (seg)
            default: begin
                case (idx)
                    0:  reset_seg_byte = "{";
                    1:  reset_seg_byte = "\"";
                    2:  reset_seg_byte = "c";
                    3:  reset_seg_byte = "m";
                    4:  reset_seg_byte = "d";
                    5:  reset_seg_byte = "\"";
                    6:  reset_seg_byte = ":";
                    7:  reset_seg_byte = "\"";
                    8:  reset_seg_byte = "R";
                    9:  reset_seg_byte = "E";
                    10: reset_seg_byte = "S";
                    11: reset_seg_byte = "E";
                    12: reset_seg_byte = "T";
                    13: reset_seg_byte = "\"";
                    14: reset_seg_byte = "}";
                    default: reset_seg_byte = 8'h0A;
                endcase
            end
        endcase
    endfunction

    function automatic logic [5:0] seg_len_now(
        input logic is_play_v,
        input logic is_reset_v,
        input logic [5:0] seg_v,
        input play_cfg_t play_cfg_v
    );
        if (is_reset_v) begin
            seg_len_now = reset_seg_len(seg_v);
        end else if (is_play_v) begin
            seg_len_now = play_seg_len(seg_v, play_cfg_v);
        end else begin
            seg_len_now = meas_seg_len(seg_v);
        end
    endfunction

    function automatic logic last_seg_now(
        input logic is_play_v,
        input logic is_reset_v,
        input logic [5:0] seg_v
    );
        if (is_reset_v) begin
            last_seg_now = 1'b1;
        end else if (is_play_v) begin
            last_seg_now = (seg_v == 6'd16);
        end else begin
            last_seg_now = (seg_v == 6'd8);
        end
    endfunction

    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
            state_r       <= FmtStateIdle;
            is_play_r     <= 1'b0;
            is_reset_r    <= 1'b0;
            cfg_index_r   <= 4'd0;
            play_cfg_r    <= '0;
            measure_cfg_r <= '0;
            seg_r         <= '0;
            char_idx_r    <= '0;
            done_pulse    <= 1'b0;
        end else begin
            done_pulse <= 1'b0;

            case (state_r)
                FmtStateIdle: begin
                    if (start) begin
                        is_play_r     <= is_play;
                        is_reset_r    <= is_reset;
                        cfg_index_r   <= cfg_index;
                        play_cfg_r    <= play_cfg;
                        measure_cfg_r <= measure_cfg;
                        seg_r         <= 6'd0;
                        char_idx_r    <= 6'd0;
                        state_r       <= FmtStateSend;
                    end
                end

                FmtStateSend: begin
                    if (tx_ready) begin
                        if (char_idx_r == seg_len_now(is_play_r, is_reset_r, seg_r, play_cfg_r) - 1'b1) begin
                            if (last_seg_now(is_play_r, is_reset_r, seg_r)) begin
                                state_r    <= FmtStateDone;
                                done_pulse <= 1'b1;
                            end else begin
                                seg_r      <= seg_r + 1'b1;
                                char_idx_r <= '0;
                            end
                        end else begin
                            char_idx_r <= char_idx_r + 1'b1;
                        end
                    end
                end

                FmtStateDone: begin
                    state_r <= FmtStateIdle;
                end

                default: begin
                    state_r <= FmtStateIdle;
                end
            endcase
        end
    end

    always_comb begin
        busy     = (state_r == FmtStateSend);
        tx_valid = (state_r == FmtStateSend);

        if (is_reset_r) begin
            tx_data = reset_seg_byte(seg_r, char_idx_r);
        end else if (is_play_r) begin
            tx_data = play_seg_byte(seg_r, char_idx_r, cfg_index_r, play_cfg_r);
        end else begin
            tx_data = meas_seg_byte(seg_r, char_idx_r, cfg_index_r, measure_cfg_r);
        end
    end

endmodule
