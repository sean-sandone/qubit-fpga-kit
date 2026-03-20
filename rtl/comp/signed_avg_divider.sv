//------------------------------------------------------------------------------
// PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
//------------------------------------------------------------------------------
// Copyright (C) 2026 Sean Sandone
// SPDX-License-Identifier: AGPL-3.0-or-later
// Please see the LICENSE file for details.
// WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// Shared signed average divider:
//     avg_out = sum_in / count_in
//
// Division is iterative and fully integer / fixed-point friendly.
//------------------------------------------------------------------------------

module signed_avg_divider #(
    parameter int unsigned SumWidth   = 32,
    parameter int unsigned CountWidth = 16,
    parameter int unsigned OutWidth   = 16
)(
    input  logic clk,
    input  logic rst_sync_n,

    input  logic                         start,
    input  logic signed [SumWidth-1:0]   sum_in,
    input  logic        [CountWidth-1:0] count_in,

    output logic                         busy,
    output logic                         done_pulse,
    output logic signed [OutWidth-1:0]   avg_out
);

    typedef enum logic [1:0] {
        DivStateIdle  = 2'd0,
        DivStateRun   = 2'd1,
        DivStateStore = 2'd2
    } div_state_t;

    div_state_t state_r;

    logic [SumWidth-1:0] dividend_r;
    logic [CountWidth-1:0] divisor_r;
    logic [SumWidth-1:0] quotient_r;
    logic [SumWidth:0]   remainder_r;
    logic [$clog2(SumWidth)-1:0] bit_idx_r;
    logic result_neg_r;

    logic [SumWidth:0]   remainder_shift_w;
    logic [SumWidth:0]   remainder_sub_w;
    logic [SumWidth-1:0] quotient_set_w;

    assign remainder_shift_w =
        {remainder_r[SumWidth-1:0], dividend_r[bit_idx_r]};

    assign remainder_sub_w =
        remainder_shift_w - {{(SumWidth-CountWidth+1){1'b0}}, divisor_r};

    assign quotient_set_w =
        quotient_r | ({{(SumWidth-1){1'b0}}, 1'b1} << bit_idx_r);

    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
            state_r      <= DivStateIdle;
            dividend_r   <= '0;
            divisor_r    <= '0;
            quotient_r   <= '0;
            remainder_r  <= '0;
            bit_idx_r    <= '0;
            result_neg_r <= 1'b0;
            avg_out      <= '0;
            done_pulse   <= 1'b0;
        end else begin
            done_pulse <= 1'b0;

            case (state_r)
                DivStateIdle: begin
                    if (start) begin
                        if (count_in == '0) begin
                            avg_out    <= '0;
                            done_pulse <= 1'b1;
                        end else begin
                            divisor_r   <= count_in;
                            quotient_r  <= '0;
                            remainder_r <= '0;
                            bit_idx_r   <= SumWidth - 1;

                            if (sum_in[SumWidth-1]) begin
                                dividend_r   <= $unsigned(-sum_in);
                                result_neg_r <= 1'b1;
                            end else begin
                                dividend_r   <= $unsigned(sum_in);
                                result_neg_r <= 1'b0;
                            end

                            state_r <= DivStateRun;
                        end
                    end
                end

                DivStateRun: begin
                    if (remainder_shift_w >= {{(SumWidth-CountWidth+1){1'b0}}, divisor_r}) begin
                        remainder_r <= remainder_sub_w;
                        quotient_r  <= quotient_set_w;
                    end else begin
                        remainder_r <= remainder_shift_w;
                    end

                    if (bit_idx_r == 0) begin
                        state_r <= DivStateStore;
                    end else begin
                        bit_idx_r <= bit_idx_r - 1'b1;
                    end
                end

                DivStateStore: begin
                    if (result_neg_r) begin
                        avg_out <= -$signed(quotient_r[OutWidth-1:0]);
                    end else begin
                        avg_out <= $signed(quotient_r[OutWidth-1:0]);
                    end

                    done_pulse <= 1'b1;
                    state_r    <= DivStateIdle;
                end

                default: begin
                    state_r <= DivStateIdle;
                end
            endcase
        end
    end

    assign busy = (state_r != DivStateIdle);

endmodule
