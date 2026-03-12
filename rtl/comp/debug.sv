module debug (
    input  logic clk,
    input  logic rst_sync_n,

    input  logic               start,
    input  logic signed [15:0] i_avg,
    input  logic signed [15:0] q_avg,

    output logic [7:0] tx_data,
    output logic       tx_valid,
    input  logic       tx_ready,

    output logic busy,
    output logic done_pulse
);

    localparam int MsgBufLen = 80;

    typedef enum logic [3:0] {
        DbgStateIdle         = 4'd0,
        DbgStateBuildPrefix0 = 4'd1,
        DbgStateBuildI       = 4'd2,
        DbgStateBuildMid0    = 4'd3,
        DbgStateBuildQ       = 4'd4,
        DbgStateBuildSuffix0 = 4'd5,
        DbgStateSend         = 4'd6,
        DbgStateDone         = 4'd7
    } dbg_state_t;

    typedef enum logic [1:0] {
        NumStateIdle       = 2'd0,
        NumStateLoadDigits = 2'd1,
        NumStateEmitDigits = 2'd2
    } num_state_t;

    dbg_state_t state_r;

    logic signed [15:0] i_avg_r;
    logic signed [15:0] q_avg_r;

    logic [7:0] msg_buf_r [MsgBufLen];
    logic [6:0] msg_len_r;
    logic [6:0] msg_wr_idx_r;
    logic [6:0] msg_tx_idx_r;

    logic [5:0] text_idx_r;

    logic [15:0] cur_mag_r;
    logic        cur_neg_r;

    logic [15:0] div10_quot_w;
    logic [3:0]  div10_rem_w;

    logic [3:0] digit_buf_r [5];
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

    function automatic logic [7:0] prefix_char(input logic [5:0] idx);
        case (idx)
            6'd0:  prefix_char = "{";
            6'd1:  prefix_char = "\"";
            6'd2:  prefix_char = "c";
            6'd3:  prefix_char = "m";
            6'd4:  prefix_char = "d";
            6'd5:  prefix_char = "\"";
            6'd6:  prefix_char = ":";
            6'd7:  prefix_char = "\"";
            6'd8:  prefix_char = "D";
            6'd9:  prefix_char = "E";
            6'd10: prefix_char = "B";
            6'd11: prefix_char = "U";
            6'd12: prefix_char = "G";
            6'd13: prefix_char = "\"";
            6'd14: prefix_char = ",";
            6'd15: prefix_char = "\"";
            6'd16: prefix_char = "m";
            6'd17: prefix_char = "s";
            6'd18: prefix_char = "g";
            6'd19: prefix_char = "\"";
            6'd20: prefix_char = ":";
            6'd21: prefix_char = "\"";
            6'd22: prefix_char = "r";
            6'd23: prefix_char = "e";
            6'd24: prefix_char = "a";
            6'd25: prefix_char = "d";
            6'd26: prefix_char = "o";
            6'd27: prefix_char = "u";
            6'd28: prefix_char = "t";
            6'd29: prefix_char = " ";
            6'd30: prefix_char = "p";
            6'd31: prefix_char = "r";
            6'd32: prefix_char = "o";
            6'd33: prefix_char = "c";
            6'd34: prefix_char = "e";
            6'd35: prefix_char = "s";
            6'd36: prefix_char = "s";
            6'd37: prefix_char = "e";
            6'd38: prefix_char = "d";
            6'd39: prefix_char = "\"";
            6'd40: prefix_char = ",";
            6'd41: prefix_char = "\"";
            6'd42: prefix_char = "I";
            6'd43: prefix_char = "_";
            6'd44: prefix_char = "a";
            6'd45: prefix_char = "v";
            6'd46: prefix_char = "g";
            6'd47: prefix_char = "\"";
            default: prefix_char = ":";
        endcase
    endfunction

    function automatic logic [7:0] mid_char(input logic [5:0] idx);
        case (idx)
            6'd0: mid_char = ",";
            6'd1: mid_char = "\"";
            6'd2: mid_char = "Q";
            6'd3: mid_char = "_";
            6'd4: mid_char = "a";
            6'd5: mid_char = "v";
            6'd6: mid_char = "g";
            6'd7: mid_char = "\"";
            default: mid_char = ":";
        endcase
    endfunction

    function automatic logic [7:0] suffix_char(input logic [5:0] idx);
        case (idx)
            6'd0: suffix_char = "}";
            default: suffix_char = 8'h0A;
        endcase
    endfunction

    assign div10_quot_w = cur_mag_r / 10;
    assign div10_rem_w  = cur_mag_r % 10;

    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
            state_r          <= DbgStateIdle;
            i_avg_r          <= '0;
            q_avg_r          <= '0;
            msg_len_r        <= '0;
            msg_wr_idx_r     <= '0;
            msg_tx_idx_r     <= '0;
            text_idx_r       <= '0;
            cur_mag_r        <= '0;
            cur_neg_r        <= 1'b0;
            digit_count_r    <= '0;
            digit_emit_idx_r <= '0;
            num_state_r      <= NumStateIdle;
            done_pulse       <= 1'b0;
        end else begin
            done_pulse <= 1'b0;

            case (state_r)
                DbgStateIdle: begin
                    if (start) begin
                        i_avg_r          <= i_avg;
                        q_avg_r          <= q_avg;
                        msg_len_r        <= '0;
                        msg_wr_idx_r     <= '0;
                        msg_tx_idx_r     <= '0;
                        text_idx_r       <= '0;
                        cur_mag_r        <= '0;
                        cur_neg_r        <= 1'b0;
                        digit_count_r    <= '0;
                        digit_emit_idx_r <= '0;
                        num_state_r      <= NumStateIdle;
                        state_r          <= DbgStateBuildPrefix0;
                    end
                end

                DbgStateBuildPrefix0: begin
                    msg_buf_r[msg_wr_idx_r] <= prefix_char(text_idx_r);
                    msg_wr_idx_r            <= msg_wr_idx_r + 1'b1;
                    msg_len_r               <= msg_len_r + 1'b1;

                    if (text_idx_r == 6'd48) begin
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
                    msg_buf_r[msg_wr_idx_r] <= mid_char(text_idx_r);
                    msg_wr_idx_r            <= msg_wr_idx_r + 1'b1;
                    msg_len_r               <= msg_len_r + 1'b1;

                    if (text_idx_r == 6'd8) begin
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
                                text_idx_r <= '0;
                                state_r    <= DbgStateBuildSuffix0;
                            end else begin
                                digit_emit_idx_r <= digit_emit_idx_r - 1'b1;
                            end
                        end

                        default: begin
                            num_state_r <= NumStateIdle;
                        end
                    endcase
                end

                DbgStateBuildSuffix0: begin
                    msg_buf_r[msg_wr_idx_r] <= suffix_char(text_idx_r);
                    msg_wr_idx_r            <= msg_wr_idx_r + 1'b1;
                    msg_len_r               <= msg_len_r + 1'b1;

                    if (text_idx_r == 6'd1) begin
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
