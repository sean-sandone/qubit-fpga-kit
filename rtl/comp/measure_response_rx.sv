//------------------------------------------------------------------------------
// PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
//------------------------------------------------------------------------------
// AUTHORS: Sean Sandone
// WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
//------------------------------------------------------------------------------

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
        RxStateSync0    = 4'd0,
        RxStateSync1    = 4'd1,
        RxStateType     = 4'd2,
        RxStateCount    = 4'd3,
        RxStatePayload  = 4'd4,
        RxStateStartDivI= 4'd5,
        RxStateWaitDivI = 4'd6,
        RxStateStartDivQ= 4'd7,
        RxStateWaitDivQ = 4'd8
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
    logic signed [MeasureAccumWidth-1:0] div_sum_mux_w;

    logic        resp_valid_r;
    logic        div_start_r;
    logic        div_busy;
    logic        div_done;
    logic signed [15:0] div_avg;

    assign i_sample_w = $signed({i_hi_r, i_lo_r});
    assign q_sample_w = $signed({q_hi_r, q_lo_r});

    assign div_sum_mux_w =
        (state_r == RxStateStartDivQ || state_r == RxStateWaitDivQ) ? q_sum_r : i_sum_r;

    signed_avg_divider #(
        .SumWidth   (MeasureAccumWidth),
        .CountWidth (8),
        .OutWidth   (16)
    ) u_signed_avg_divider (
        .clk        (clk),
        .rst_sync_n (rst_sync_n),
        .start      (div_start_r),
        .sum_in     (div_sum_mux_w),
        .count_in   (sample_count_r),
        .busy       (div_busy),
        .done_pulse (div_done),
        .avg_out    (div_avg)
    );

    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
            state_r        <= RxStateSync0;
            sample_count_r <= 8'd0;
            sample_index_r <= 8'd0;
            byte_phase_r   <= 2'd0;
            i_lo_r         <= 8'd0;
            i_hi_r         <= 8'd0;
            q_lo_r         <= 8'd0;
            q_hi_r         <= 8'd0;
            i_sum_r        <= '0;
            q_sum_r        <= '0;
            i_avg          <= '0;
            q_avg          <= '0;
            resp_valid_r   <= 1'b0;
            done_pulse     <= 1'b0;
            div_start_r    <= 1'b0;
        end else begin
            done_pulse  <= 1'b0;
            div_start_r <= 1'b0;

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
                        resp_valid_r   <= 1'b0;

                        if (rx_byte == 8'd0) begin
                            i_avg       <= '0;
                            q_avg       <= '0;
                            resp_valid_r<= 1'b1;
                            done_pulse  <= 1'b1;
                            state_r     <= RxStateSync0;
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

                                i_sum_r <= i_sum_r + $signed({i_hi_r, i_lo_r});
                                q_sum_r <= q_sum_r + $signed({rx_byte, q_lo_r});

                                if (sample_index_r == (sample_count_r - 1'b1)) begin
                                    byte_phase_r <= 2'd0;
                                    state_r      <= RxStateStartDivI;
                                end else begin
                                    sample_index_r <= sample_index_r + 1'b1;
                                    byte_phase_r   <= 2'd0;
                                end
                            end
                        endcase
                    end
                end

                RxStateStartDivI: begin
                    div_start_r <= 1'b1;
                    state_r     <= RxStateWaitDivI;
                end

                RxStateWaitDivI: begin
                    if (div_done) begin
                        i_avg   <= div_avg;
                        state_r <= RxStateStartDivQ;
                    end
                end

                RxStateStartDivQ: begin
                    div_start_r <= 1'b1;
                    state_r     <= RxStateWaitDivQ;
                end

                RxStateWaitDivQ: begin
                    if (div_done) begin
                        q_avg       <= div_avg;
                        resp_valid_r <= 1'b1;
                        done_pulse   <= 1'b1;
                        state_r      <= RxStateSync0;
                    end
                end

                default: begin
                    state_r <= RxStateSync0;
                end
            endcase
        end
    end

    assign busy        = (state_r != RxStateSync0) || div_busy;
    assign resp_valid  = resp_valid_r;
    assign sample_count = sample_count_r;

endmodule
