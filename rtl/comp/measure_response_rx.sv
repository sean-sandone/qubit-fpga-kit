module measure_response_rx (
    input  logic clk,
    input  logic rst_sync_n,

    input  logic       rx_byte_valid,
    input  logic [7:0] rx_byte,

    output logic busy,
    output logic done_pulse,

    output logic        resp_valid,
    output logic [7:0]  sample_count,
    output logic signed [15:0] i_avg,
    output logic signed [15:0] q_avg
);

    import rtl_pkg::*;

    typedef enum logic [3:0] {
        RxStateSync0      = 4'd0,
        RxStateSync1      = 4'd1,
        RxStateType       = 4'd2,
        RxStateCount      = 4'd3,
        RxStatePayload    = 4'd4,
        RxStateDivPrepI   = 4'd5,
        RxStateDivRunI    = 4'd6,
        RxStateDivStoreI  = 4'd7,
        RxStateDivPrepQ   = 4'd8,
        RxStateDivRunQ    = 4'd9,
        RxStateDivStoreQ  = 4'd10,
        RxStateDone       = 4'd11
    } rx_state_t;

    rx_state_t state_r;

    logic [7:0] sample_count_r;
    logic [7:0] sample_index_r;
    logic [1:0] byte_phase_r;

    logic [7:0] i_lo_r;
    logic [7:0] i_hi_r;
    logic [7:0] q_lo_r;
    logic [7:0] q_hi_r;

    logic signed [15:0] i_sample_w;
    logic signed [15:0] q_sample_w;

    logic signed [MeasureAccumWidth-1:0] i_sum_r;
    logic signed [MeasureAccumWidth-1:0] q_sum_r;

    logic signed [MeasureAccumWidth-1:0] i_sum_final_r;
    logic signed [MeasureAccumWidth-1:0] q_sum_final_r;

    logic signed [15:0] i_avg_r;
    logic signed [15:0] q_avg_r;
    logic               resp_valid_r;

    logic [MeasureAccumWidth-1:0] div_dividend_r;
    logic [7:0]                   div_divisor_r;
    logic [MeasureAccumWidth-1:0] div_quotient_r;
    logic [MeasureAccumWidth:0]   div_remainder_r;
    logic [5:0]                   div_bit_idx_r;
    logic                         div_result_neg_r;

    logic [MeasureAccumWidth:0] div_remainder_shift_w;
    logic [MeasureAccumWidth:0] div_remainder_sub_w;
    logic [MeasureAccumWidth-1:0] div_quotient_set_w;

    assign i_sample_w = $signed({i_hi_r, i_lo_r});
    assign q_sample_w = $signed({q_hi_r, q_lo_r});

    assign div_remainder_shift_w =
        {div_remainder_r[MeasureAccumWidth-1:0], div_dividend_r[div_bit_idx_r]};

    assign div_remainder_sub_w = div_remainder_shift_w - {{MeasureAccumWidth-7{1'b0}}, div_divisor_r};

    assign div_quotient_set_w = div_quotient_r | ({{(MeasureAccumWidth-1){1'b0}}, 1'b1} << div_bit_idx_r);

    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
            state_r          <= RxStateSync0;
            sample_count_r   <= 8'd0;
            sample_index_r   <= 8'd0;
            byte_phase_r     <= 2'd0;
            i_lo_r           <= 8'd0;
            i_hi_r           <= 8'd0;
            q_lo_r           <= 8'd0;
            q_hi_r           <= 8'd0;
            i_sum_r          <= '0;
            q_sum_r          <= '0;
            i_sum_final_r    <= '0;
            q_sum_final_r    <= '0;
            i_avg_r          <= '0;
            q_avg_r          <= '0;
            resp_valid_r     <= 1'b0;
            done_pulse       <= 1'b0;
            div_dividend_r   <= '0;
            div_divisor_r    <= 8'd0;
            div_quotient_r   <= '0;
            div_remainder_r  <= '0;
            div_bit_idx_r    <= 6'd0;
            div_result_neg_r <= 1'b0;
        end else begin
            done_pulse <= 1'b0;

            case (state_r)
                RxStateSync0: begin
                    if (rx_byte_valid && (rx_byte == MeasureRespSync0)) begin
                        state_r <= RxStateSync1;
                    end
                end

                RxStateSync1: begin
                    if (rx_byte_valid) begin
                        if (rx_byte == MeasureRespSync1) begin
                            state_r <= RxStateType;
                        end else if (rx_byte == MeasureRespSync0) begin
                            state_r <= RxStateSync1;
                        end else begin
                            state_r <= RxStateSync0;
                        end
                    end
                end

                RxStateType: begin
                    if (rx_byte_valid) begin
                        if (rx_byte == MeasureRespType) begin
                            state_r <= RxStateCount;
                        end else begin
                            state_r <= RxStateSync0;
                        end
                    end
                end

                RxStateCount: begin
                    if (rx_byte_valid) begin
                        sample_count_r <= rx_byte;
                        sample_index_r <= 8'd0;
                        byte_phase_r   <= 2'd0;
                        i_sum_r        <= '0;
                        q_sum_r        <= '0;
                        i_sum_final_r  <= '0;
                        q_sum_final_r  <= '0;
                        resp_valid_r   <= 1'b0;

                        if (rx_byte == 8'd0) begin
                            i_avg_r      <= '0;
                            q_avg_r      <= '0;
                            resp_valid_r <= 1'b1;
                            done_pulse   <= 1'b1;
                            state_r      <= RxStateSync0;
                        end else begin
                            state_r <= RxStatePayload;
                        end
                    end
                end

                RxStatePayload: begin
                    if (rx_byte_valid) begin
                        case (byte_phase_r)
                            2'd0: begin
                                i_lo_r       <= rx_byte;
                                byte_phase_r <= 2'd1;
                            end

                            2'd1: begin
                                i_hi_r       <= rx_byte;
                                byte_phase_r <= 2'd2;
                            end

                            2'd2: begin
                                q_lo_r       <= rx_byte;
                                byte_phase_r <= 2'd3;
                            end

                            default: begin
                                q_hi_r <= rx_byte;

                                if (sample_index_r == (sample_count_r - 1'b1)) begin
                                    i_sum_final_r <= i_sum_r + $signed({i_hi_r, i_lo_r});
                                    q_sum_final_r <= q_sum_r + $signed({rx_byte, q_lo_r});
                                    byte_phase_r  <= 2'd0;
                                    state_r       <= RxStateDivPrepI;
                                end else begin
                                    i_sum_r        <= i_sum_r + $signed({i_hi_r, i_lo_r});
                                    q_sum_r        <= q_sum_r + $signed({rx_byte, q_lo_r});
                                    sample_index_r <= sample_index_r + 1'b1;
                                    byte_phase_r   <= 2'd0;
                                end
                            end
                        endcase
                    end
                end

                RxStateDivPrepI: begin
                    div_divisor_r   <= sample_count_r;
                    div_quotient_r  <= '0;
                    div_remainder_r <= '0;
                    div_bit_idx_r   <= MeasureAccumWidth - 1;

                    if (i_sum_final_r[MeasureAccumWidth-1]) begin
                        div_dividend_r   <= $unsigned(-i_sum_final_r);
                        div_result_neg_r <= 1'b1;
                    end else begin
                        div_dividend_r   <= $unsigned(i_sum_final_r);
                        div_result_neg_r <= 1'b0;
                    end

                    state_r <= RxStateDivRunI;
                end

                RxStateDivRunI: begin
                    if (div_remainder_shift_w >= {{MeasureAccumWidth-7{1'b0}}, div_divisor_r}) begin
                        div_remainder_r <= div_remainder_sub_w;
                        div_quotient_r  <= div_quotient_set_w;
                    end else begin
                        div_remainder_r <= div_remainder_shift_w;
                    end

                    if (div_bit_idx_r == 0) begin
                        state_r <= RxStateDivStoreI;
                    end else begin
                        div_bit_idx_r <= div_bit_idx_r - 1'b1;
                    end
                end

                RxStateDivStoreI: begin
                    if (div_result_neg_r) begin
                        i_avg_r <= -$signed(div_quotient_r[15:0]);
                    end else begin
                        i_avg_r <= $signed(div_quotient_r[15:0]);
                    end

                    state_r <= RxStateDivPrepQ;
                end

                RxStateDivPrepQ: begin
                    div_divisor_r   <= sample_count_r;
                    div_quotient_r  <= '0;
                    div_remainder_r <= '0;
                    div_bit_idx_r   <= MeasureAccumWidth - 1;

                    if (q_sum_final_r[MeasureAccumWidth-1]) begin
                        div_dividend_r   <= $unsigned(-q_sum_final_r);
                        div_result_neg_r <= 1'b1;
                    end else begin
                        div_dividend_r   <= $unsigned(q_sum_final_r);
                        div_result_neg_r <= 1'b0;
                    end

                    state_r <= RxStateDivRunQ;
                end

                RxStateDivRunQ: begin
                    if (div_remainder_shift_w >= {{MeasureAccumWidth-7{1'b0}}, div_divisor_r}) begin
                        div_remainder_r <= div_remainder_sub_w;
                        div_quotient_r  <= div_quotient_set_w;
                    end else begin
                        div_remainder_r <= div_remainder_shift_w;
                    end

                    if (div_bit_idx_r == 0) begin
                        state_r <= RxStateDivStoreQ;
                    end else begin
                        div_bit_idx_r <= div_bit_idx_r - 1'b1;
                    end
                end

                RxStateDivStoreQ: begin
                    if (div_result_neg_r) begin
                        q_avg_r <= -$signed(div_quotient_r[15:0]);
                    end else begin
                        q_avg_r <= $signed(div_quotient_r[15:0]);
                    end

                    state_r <= RxStateDone;
                end

                RxStateDone: begin
                    resp_valid_r <= 1'b1;
                    done_pulse   <= 1'b1;
                    state_r      <= RxStateSync0;
                end

                default: begin
                    state_r <= RxStateSync0;
                end
            endcase
        end
    end

    always_comb begin
        case (state_r)
            RxStateSync0: busy = 1'b0;
            default:      busy = 1'b1;
        endcase
    end

    assign resp_valid   = resp_valid_r;
    assign sample_count = sample_count_r;
    assign i_avg        = i_avg_r;
    assign q_avg        = q_avg_r;

endmodule
