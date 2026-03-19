//------------------------------------------------------------------------------
// PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
//------------------------------------------------------------------------------
// AUTHORS: Sean Sandone
// WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
//------------------------------------------------------------------------------

module debug (
    input  logic clk,
    input  logic rst_sync_n,

    input  logic               start,
    input  logic               cal_update,
    input  logic signed [15:0] i_avg,
    input  logic signed [15:0] q_avg,
    input  logic signed [15:0] cal_i_threshold,
    input  logic               cal_state_polarity,
    input  logic               meas_state,
    input  logic               meas_state_valid,

    output logic [7:0] tx_data,
    output logic       tx_valid,
    input  logic       tx_ready,

    output logic busy,
    output logic done_pulse
);

    localparam int MsgBufLen = 128;

    typedef enum logic [3:0] {
        DbgStateIdle         = 4'd0,
        DbgStateBuildPrefix0 = 4'd1,
        DbgStateBuildI       = 4'd2,
        DbgStateBuildMid0    = 4'd3,
        DbgStateBuildQ       = 4'd4,
        DbgStateBuildMid1    = 4'd5,
        DbgStateBuildThresh  = 4'd6,
        DbgStateBuildMid2    = 4'd7,
        DbgStateBuildPol     = 4'd8,
        DbgStateBuildMid3    = 4'd9,
        DbgStateBuildMeas    = 4'd10,
        DbgStateBuildSuffix0 = 4'd11,
        DbgStateSend         = 4'd12,
        DbgStateDone         = 4'd13
    } dbg_state_t;

    typedef enum logic [1:0] {
        NumStateIdle       = 2'd0,
        NumStateLoadDigits = 2'd1,
        NumStateEmitDigits = 2'd2
    } num_state_t;

    dbg_state_t state_r;

    logic               cal_update_r;
    logic signed [15:0] i_avg_r;
    logic signed [15:0] q_avg_r;
    logic signed [15:0] cal_i_threshold_r;
    logic               cal_state_polarity_r;
    logic               meas_state_r;
    logic               meas_state_valid_r;

    logic [7:0] msg_buf_r [MsgBufLen];
    logic [6:0] msg_len_r;
    logic [6:0] msg_wr_idx_r;
    logic [6:0] msg_tx_idx_r;

    logic [6:0] text_idx_r;

    logic [15:0] cur_mag_r;
    logic        cur_neg_r;

    logic [15:0] div10_quot_w;
    logic [3:0]  div10_rem_w;

    logic [3:0] digit_buf_r [6];
    logic [2:0] digit_count_r;
    logic [2:0] digit_emit_idx_r;
    num_state_t num_state_r;

    function automatic [15:0] abs16_u(input logic signed [15:0] value);
        begin
            if (value == 16'sh8000) begin
                abs16_u = 16'd32768;
            end else if (value < 0) begin
                abs16_u = $unsigned(-value);
            end else begin
                abs16_u = $unsigned(value);
            end
        end
    endfunction

    function automatic logic [7:0] digit_char(input logic [3:0] digit);
        digit_char = "0" + digit;
    endfunction

    function automatic logic [7:0] prefix_char(
        input logic       cal_update_sel,
        input logic [6:0] idx
    );
        if (!cal_update_sel) begin
            case (idx)
                7'd0:  prefix_char = "{";
                7'd1:  prefix_char = "\"";
                7'd2:  prefix_char = "c";
                7'd3:  prefix_char = "m";
                7'd4:  prefix_char = "d";
                7'd5:  prefix_char = "\"";
                7'd6:  prefix_char = ":";
                7'd7:  prefix_char = "\"";
                7'd8:  prefix_char = "D";
                7'd9:  prefix_char = "E";
                7'd10: prefix_char = "B";
                7'd11: prefix_char = "U";
                7'd12: prefix_char = "G";
                7'd13: prefix_char = "\"";
                7'd14: prefix_char = ",";
                7'd15: prefix_char = "\"";
                7'd16: prefix_char = "m";
                7'd17: prefix_char = "s";
                7'd18: prefix_char = "g";
                7'd19: prefix_char = "\"";
                7'd20: prefix_char = ":";
                7'd21: prefix_char = "\"";
                7'd22: prefix_char = "r";
                7'd23: prefix_char = "e";
                7'd24: prefix_char = "a";
                7'd25: prefix_char = "d";
                7'd26: prefix_char = "o";
                7'd27: prefix_char = "u";
                7'd28: prefix_char = "t";
                7'd29: prefix_char = " ";
                7'd30: prefix_char = "p";
                7'd31: prefix_char = "r";
                7'd32: prefix_char = "o";
                7'd33: prefix_char = "c";
                7'd34: prefix_char = "e";
                7'd35: prefix_char = "s";
                7'd36: prefix_char = "s";
                7'd37: prefix_char = "e";
                7'd38: prefix_char = "d";
                7'd39: prefix_char = "\"";
                7'd40: prefix_char = ",";
                7'd41: prefix_char = "\"";
                7'd42: prefix_char = "I";
                7'd43: prefix_char = "_";
                7'd44: prefix_char = "a";
                7'd45: prefix_char = "v";
                7'd46: prefix_char = "g";
                7'd47: prefix_char = "\"";
                default: prefix_char = ":";
            endcase
        end else begin
            case (idx)
                7'd0:  prefix_char = "{";
                7'd1:  prefix_char = "\"";
                7'd2:  prefix_char = "c";
                7'd3:  prefix_char = "m";
                7'd4:  prefix_char = "d";
                7'd5:  prefix_char = "\"";
                7'd6:  prefix_char = ":";
                7'd7:  prefix_char = "\"";
                7'd8:  prefix_char = "D";
                7'd9:  prefix_char = "E";
                7'd10: prefix_char = "B";
                7'd11: prefix_char = "U";
                7'd12: prefix_char = "G";
                7'd13: prefix_char = "\"";
                7'd14: prefix_char = ",";
                7'd15: prefix_char = "\"";
                7'd16: prefix_char = "m";
                7'd17: prefix_char = "s";
                7'd18: prefix_char = "g";
                7'd19: prefix_char = "\"";
                7'd20: prefix_char = ":";
                7'd21: prefix_char = "\"";
                7'd22: prefix_char = "c";
                7'd23: prefix_char = "a";
                7'd24: prefix_char = "l";
                7'd25: prefix_char = "i";
                7'd26: prefix_char = "b";
                7'd27: prefix_char = "r";
                7'd28: prefix_char = "a";
                7'd29: prefix_char = "t";
                7'd30: prefix_char = "i";
                7'd31: prefix_char = "o";
                7'd32: prefix_char = "n";
                7'd33: prefix_char = " ";
                7'd34: prefix_char = "u";
                7'd35: prefix_char = "p";
                7'd36: prefix_char = "d";
                7'd37: prefix_char = "a";
                7'd38: prefix_char = "t";
                7'd39: prefix_char = "e";
                7'd40: prefix_char = "d";
                7'd41: prefix_char = "\"";
                7'd42: prefix_char = ",";
                7'd43: prefix_char = "\"";
                7'd44: prefix_char = "I";
                7'd45: prefix_char = "_";
                7'd46: prefix_char = "a";
                7'd47: prefix_char = "v";
                7'd48: prefix_char = "g";
                7'd49: prefix_char = "\"";
                default: prefix_char = ":";
            endcase
        end
    endfunction

    function automatic logic [7:0] mid0_char(
        input logic       cal_update_sel,
        input logic [6:0] idx
    );
        if (!cal_update_sel) begin
            case (idx)
                7'd0: mid0_char = ",";
                7'd1: mid0_char = "\"";
                7'd2: mid0_char = "Q";
                7'd3: mid0_char = "_";
                7'd4: mid0_char = "a";
                7'd5: mid0_char = "v";
                7'd6: mid0_char = "g";
                7'd7: mid0_char = "\"";
                default: mid0_char = ":";
            endcase
        end else begin
            case (idx)
                7'd0: mid0_char = ",";
                7'd1: mid0_char = "\"";
                7'd2: mid0_char = "Q";
                7'd3: mid0_char = "_";
                7'd4: mid0_char = "a";
                7'd5: mid0_char = "v";
                7'd6: mid0_char = "g";
                7'd7: mid0_char = "\"";
                default: mid0_char = ":";
            endcase
        end
    endfunction

    function automatic logic [7:0] mid1_char(input logic [6:0] idx);
        case (idx)
            7'd0:  mid1_char = ",";
            7'd1:  mid1_char = "\"";
            7'd2:  mid1_char = "c";
            7'd3:  mid1_char = "a";
            7'd4:  mid1_char = "l";
            7'd5:  mid1_char = "_";
            7'd6:  mid1_char = "i";
            7'd7:  mid1_char = "_";
            7'd8:  mid1_char = "t";
            7'd9:  mid1_char = "h";
            7'd10: mid1_char = "r";
            7'd11: mid1_char = "e";
            7'd12: mid1_char = "s";
            7'd13: mid1_char = "h";
            7'd14: mid1_char = "o";
            7'd15: mid1_char = "l";
            7'd16: mid1_char = "d";
            7'd17: mid1_char = "\"";
            default: mid1_char = ":";
        endcase
    endfunction

    function automatic logic [7:0] mid2_char(input logic [6:0] idx);
        case (idx)
            7'd0:  mid2_char = ",";
            7'd1:  mid2_char = "\"";
            7'd2:  mid2_char = "c";
            7'd3:  mid2_char = "a";
            7'd4:  mid2_char = "l";
            7'd5:  mid2_char = "_";
            7'd6:  mid2_char = "s";
            7'd7:  mid2_char = "t";
            7'd8:  mid2_char = "a";
            7'd9:  mid2_char = "t";
            7'd10: mid2_char = "e";
            7'd11: mid2_char = "_";
            7'd12: mid2_char = "p";
            7'd13: mid2_char = "o";
            7'd14: mid2_char = "l";
            7'd15: mid2_char = "a";
            7'd16: mid2_char = "r";
            7'd17: mid2_char = "i";
            7'd18: mid2_char = "t";
            7'd19: mid2_char = "y";
            7'd20: mid2_char = "\"";
            default: mid2_char = ":";
        endcase
    endfunction

    function automatic logic [7:0] mid3_char(input logic [6:0] idx);
        case (idx)
            7'd0:  mid3_char = ",";
            7'd1:  mid3_char = "\"";
            7'd2:  mid3_char = "m";
            7'd3:  mid3_char = "e";
            7'd4:  mid3_char = "a";
            7'd5:  mid3_char = "s";
            7'd6:  mid3_char = "_";
            7'd7:  mid3_char = "s";
            7'd8:  mid3_char = "t";
            7'd9:  mid3_char = "a";
            7'd10: mid3_char = "t";
            7'd11: mid3_char = "e";
            7'd12: mid3_char = "\"";
            default: mid3_char = ":";
        endcase
    endfunction

    function automatic logic [7:0] suffix_char(input logic [6:0] idx);
        case (idx)
            7'd0: suffix_char = "}";
            default: suffix_char = 8'h0A;
        endcase
    endfunction

    assign div10_quot_w = cur_mag_r / 10;
    assign div10_rem_w  = cur_mag_r % 10;

    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
            state_r                <= DbgStateIdle;
            cal_update_r           <= 1'b0;
            i_avg_r                <= '0;
            q_avg_r                <= '0;
            cal_i_threshold_r      <= '0;
            cal_state_polarity_r   <= 1'b0;
            meas_state_r           <= 1'b0;
            meas_state_valid_r     <= 1'b0;
            msg_len_r              <= '0;
            msg_wr_idx_r           <= '0;
            msg_tx_idx_r           <= '0;
            text_idx_r             <= '0;
            cur_mag_r              <= '0;
            cur_neg_r              <= 1'b0;
            digit_count_r          <= '0;
            digit_emit_idx_r       <= '0;
            num_state_r            <= NumStateIdle;
            done_pulse             <= 1'b0;
        end else begin
            done_pulse <= 1'b0;

            case (state_r)
                DbgStateIdle: begin
                    if (start) begin
                        cal_update_r         <= cal_update;
                        i_avg_r              <= i_avg;
                        q_avg_r              <= q_avg;
                        cal_i_threshold_r    <= cal_i_threshold;
                        cal_state_polarity_r <= cal_state_polarity;
                        meas_state_r         <= meas_state;
                        meas_state_valid_r   <= meas_state_valid;
                        msg_len_r            <= '0;
                        msg_wr_idx_r         <= '0;
                        msg_tx_idx_r         <= '0;
                        text_idx_r           <= '0;
                        cur_mag_r            <= '0;
                        cur_neg_r            <= 1'b0;
                        digit_count_r        <= '0;
                        digit_emit_idx_r     <= '0;
                        num_state_r          <= NumStateIdle;
                        state_r              <= DbgStateBuildPrefix0;
                    end
                end

                DbgStateBuildPrefix0: begin
                    msg_buf_r[msg_wr_idx_r] <= prefix_char(cal_update_r, text_idx_r);
                    msg_wr_idx_r            <= msg_wr_idx_r + 1'b1;
                    msg_len_r               <= msg_len_r + 1'b1;

                    if ((!cal_update_r && (text_idx_r == 7'd48)) ||
                        ( cal_update_r && (text_idx_r == 7'd50))) begin
                        cur_mag_r        <= abs16_u(i_avg_r);
                        cur_neg_r        <= (i_avg_r < 0);
                        digit_count_r    <= '0;
                        digit_emit_idx_r <= '0;
                        num_state_r      <= NumStateLoadDigits;
                        state_r          <= DbgStateBuildI;
                    end else begin
                        text_idx_r <= text_idx_r + 1'b1;
                    end
                end

                DbgStateBuildI: begin
                    case (num_state_r)
                        NumStateLoadDigits: begin
                            if (cur_neg_r) begin
                                msg_buf_r[msg_wr_idx_r] <= "-";
                                msg_wr_idx_r            <= msg_wr_idx_r + 1'b1;
                                msg_len_r               <= msg_len_r + 1'b1;
                                cur_neg_r               <= 1'b0;
                            end else begin
                                digit_buf_r[digit_count_r] <= div10_rem_w;
                                digit_count_r              <= digit_count_r + 1'b1;

                                if (div10_quot_w == 0) begin
                                    digit_emit_idx_r <= digit_count_r;
                                    num_state_r      <= NumStateEmitDigits;
                                end else begin
                                    cur_mag_r <= div10_quot_w;
                                end
                            end
                        end

                        NumStateEmitDigits: begin
                            msg_buf_r[msg_wr_idx_r] <= digit_char(digit_buf_r[digit_emit_idx_r]);
                            msg_wr_idx_r            <= msg_wr_idx_r + 1'b1;
                            msg_len_r               <= msg_len_r + 1'b1;

                            if (digit_emit_idx_r == 0) begin
                                text_idx_r <= '0;
                                state_r    <= DbgStateBuildMid0;
                            end else begin
                                digit_emit_idx_r <= digit_emit_idx_r - 1'b1;
                            end
                        end

                        default: begin
                            num_state_r <= NumStateIdle;
                        end
                    endcase
                end

                DbgStateBuildMid0: begin
                    msg_buf_r[msg_wr_idx_r] <= mid0_char(cal_update_r, text_idx_r);
                    msg_wr_idx_r            <= msg_wr_idx_r + 1'b1;
                    msg_len_r               <= msg_len_r + 1'b1;

                    if (text_idx_r == 7'd8) begin
                        cur_mag_r        <= abs16_u(q_avg_r);
                        cur_neg_r        <= (q_avg_r < 0);
                        digit_count_r    <= '0;
                        digit_emit_idx_r <= '0;
                        num_state_r      <= NumStateLoadDigits;
                        state_r          <= DbgStateBuildQ;
                    end else begin
                        text_idx_r <= text_idx_r + 1'b1;
                    end
                end

                DbgStateBuildQ: begin
                    case (num_state_r)
                        NumStateLoadDigits: begin
                            if (cur_neg_r) begin
                                msg_buf_r[msg_wr_idx_r] <= "-";
                                msg_wr_idx_r            <= msg_wr_idx_r + 1'b1;
                                msg_len_r               <= msg_len_r + 1'b1;
                                cur_neg_r               <= 1'b0;
                            end else begin
                                digit_buf_r[digit_count_r] <= div10_rem_w;
                                digit_count_r              <= digit_count_r + 1'b1;

                                if (div10_quot_w == 0) begin
                                    digit_emit_idx_r <= digit_count_r;
                                    num_state_r      <= NumStateEmitDigits;
                                end else begin
                                    cur_mag_r <= div10_quot_w;
                                end
                            end
                        end

                        NumStateEmitDigits: begin
                            msg_buf_r[msg_wr_idx_r] <= digit_char(digit_buf_r[digit_emit_idx_r]);
                            msg_wr_idx_r            <= msg_wr_idx_r + 1'b1;
                            msg_len_r               <= msg_len_r + 1'b1;

                            if (digit_emit_idx_r == 0) begin
                                if (cal_update_r) begin
                                    text_idx_r <= '0;
                                    state_r    <= DbgStateBuildMid1;
                                end else begin
                                    text_idx_r <= '0;
                                    state_r    <= DbgStateBuildMid3;
                                end
                            end else begin
                                digit_emit_idx_r <= digit_emit_idx_r - 1'b1;
                            end
                        end

                        default: begin
                            num_state_r <= NumStateIdle;
                        end
                    endcase
                end

                DbgStateBuildMid1: begin
                    msg_buf_r[msg_wr_idx_r] <= mid1_char(text_idx_r);
                    msg_wr_idx_r            <= msg_wr_idx_r + 1'b1;
                    msg_len_r               <= msg_len_r + 1'b1;

                    if (text_idx_r == 7'd18) begin
                        cur_mag_r        <= abs16_u(cal_i_threshold_r);
                        cur_neg_r        <= (cal_i_threshold_r < 0);
                        digit_count_r    <= '0;
                        digit_emit_idx_r <= '0;
                        num_state_r      <= NumStateLoadDigits;
                        state_r          <= DbgStateBuildThresh;
                    end else begin
                        text_idx_r <= text_idx_r + 1'b1;
                    end
                end

                DbgStateBuildThresh: begin
                    case (num_state_r)
                        NumStateLoadDigits: begin
                            if (cur_neg_r) begin
                                msg_buf_r[msg_wr_idx_r] <= "-";
                                msg_wr_idx_r            <= msg_wr_idx_r + 1'b1;
                                msg_len_r               <= msg_len_r + 1'b1;
                                cur_neg_r               <= 1'b0;
                            end else begin
                                digit_buf_r[digit_count_r] <= div10_rem_w;
                                digit_count_r              <= digit_count_r + 1'b1;

                                if (div10_quot_w == 0) begin
                                    digit_emit_idx_r <= digit_count_r;
                                    num_state_r      <= NumStateEmitDigits;
                                end else begin
                                    cur_mag_r <= div10_quot_w;
                                end
                            end
                        end

                        NumStateEmitDigits: begin
                            msg_buf_r[msg_wr_idx_r] <= digit_char(digit_buf_r[digit_emit_idx_r]);
                            msg_wr_idx_r            <= msg_wr_idx_r + 1'b1;
                            msg_len_r               <= msg_len_r + 1'b1;

                            if (digit_emit_idx_r == 0) begin
                                text_idx_r <= '0;
                                state_r    <= DbgStateBuildMid2;
                            end else begin
                                digit_emit_idx_r <= digit_emit_idx_r - 1'b1;
                            end
                        end

                        default: begin
                            num_state_r <= NumStateIdle;
                        end
                    endcase
                end

                DbgStateBuildMid2: begin
                    msg_buf_r[msg_wr_idx_r] <= mid2_char(text_idx_r);
                    msg_wr_idx_r            <= msg_wr_idx_r + 1'b1;
                    msg_len_r               <= msg_len_r + 1'b1;

                    if (text_idx_r == 7'd21) begin
                        state_r <= DbgStateBuildPol;
                    end else begin
                        text_idx_r <= text_idx_r + 1'b1;
                    end
                end

                DbgStateBuildPol: begin
                    msg_buf_r[msg_wr_idx_r] <= cal_state_polarity_r ? "1" : "0";
                    msg_wr_idx_r            <= msg_wr_idx_r + 1'b1;
                    msg_len_r               <= msg_len_r + 1'b1;
                    text_idx_r              <= '0;
                    state_r                 <= DbgStateBuildSuffix0;
                end

                DbgStateBuildMid3: begin
                    msg_buf_r[msg_wr_idx_r] <= mid3_char(text_idx_r);
                    msg_wr_idx_r            <= msg_wr_idx_r + 1'b1;
                    msg_len_r               <= msg_len_r + 1'b1;

                    if (text_idx_r == 7'd13) begin
                        text_idx_r <= '0;
                        state_r    <= DbgStateBuildMeas;
                    end else begin
                        text_idx_r <= text_idx_r + 1'b1;
                    end
                end

                DbgStateBuildMeas: begin
                    if (meas_state_valid_r) begin
                        msg_buf_r[msg_wr_idx_r] <= meas_state_r ? "1" : "0";
                        msg_wr_idx_r            <= msg_wr_idx_r + 1'b1;
                        msg_len_r               <= msg_len_r + 1'b1;
                        text_idx_r              <= '0;
                        state_r                 <= DbgStateBuildSuffix0;
                    end else begin
                        case (text_idx_r)
                            7'd0: msg_buf_r[msg_wr_idx_r] <= "\"";
                            7'd1: msg_buf_r[msg_wr_idx_r] <= "n";
                            7'd2: msg_buf_r[msg_wr_idx_r] <= "a";
                            default: msg_buf_r[msg_wr_idx_r] <= "\"";
                        endcase
                        msg_wr_idx_r <= msg_wr_idx_r + 1'b1;
                        msg_len_r    <= msg_len_r + 1'b1;

                        if (text_idx_r == 7'd3) begin
                            text_idx_r <= '0;
                            state_r    <= DbgStateBuildSuffix0;
                        end else begin
                            text_idx_r <= text_idx_r + 1'b1;
                        end
                    end
                end

                DbgStateBuildSuffix0: begin
                    msg_buf_r[msg_wr_idx_r] <= suffix_char(text_idx_r);
                    msg_wr_idx_r            <= msg_wr_idx_r + 1'b1;
                    msg_len_r               <= msg_len_r + 1'b1;

                    if (text_idx_r == 7'd1) begin
                        msg_tx_idx_r <= '0;
                        state_r      <= DbgStateSend;
                    end else begin
                        text_idx_r <= text_idx_r + 1'b1;
                    end
                end

                DbgStateSend: begin
                    if (tx_ready) begin
                        if (msg_tx_idx_r + 1'b1 >= msg_len_r) begin
                            state_r <= DbgStateDone;
                        end else begin
                            msg_tx_idx_r <= msg_tx_idx_r + 1'b1;
                        end
                    end
                end

                DbgStateDone: begin
                    done_pulse <= 1'b1;
                    state_r    <= DbgStateIdle;
                end

                default: begin
                    state_r <= DbgStateIdle;
                end
            endcase
        end
    end

    always_comb begin
        tx_data  = msg_buf_r[msg_tx_idx_r];
        tx_valid = (state_r == DbgStateSend);
        busy     = (state_r != DbgStateIdle);
    end

endmodule
