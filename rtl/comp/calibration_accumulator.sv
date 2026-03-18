//------------------------------------------------------------------------------
// PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
//------------------------------------------------------------------------------
// AUTHORS: Sean Sandone
// WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// Accumulates per-readout I_avg / Q_avg values across a calibration loop,
// then computes final average I/Q using the shared signed_avg_divider.
//------------------------------------------------------------------------------

module calibration_accumulator (
    input  logic clk,
    input  logic rst_sync_n,

    input  logic clear,
    input  logic push,
    input  logic finalize,

    input  logic signed [15:0] i_in,
    input  logic signed [15:0] q_in,

    output logic        busy,
    output logic        done_pulse,
    output logic        avg_valid,
    output logic [15:0] sample_count,
    output logic signed [15:0] i_avg,
    output logic signed [15:0] q_avg
);

    import rtl_pkg::*;

    typedef enum logic [2:0] {
        CalStateIdle       = 3'd0,
        CalStateStartDivI  = 3'd1,
        CalStateWaitDivI   = 3'd2,
        CalStateStartDivQ  = 3'd3,
        CalStateWaitDivQ   = 3'd4
    } cal_state_t;

    cal_state_t state_r;

    logic signed [MeasureAccumWidth-1:0] i_sum_r;
    logic signed [MeasureAccumWidth-1:0] q_sum_r;
    logic [15:0]                         sample_count_r;

    logic        div_start_r;
    logic        div_done;
    logic        div_busy;
    logic signed [15:0] div_avg;
    logic signed [MeasureAccumWidth-1:0] div_sum_mux_w;

    assign div_sum_mux_w = (state_r == CalStateStartDivQ || state_r == CalStateWaitDivQ) ? q_sum_r : i_sum_r;

    signed_avg_divider #(
        .SumWidth   (MeasureAccumWidth),
        .CountWidth (16),
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
            state_r         <= CalStateIdle;
            i_sum_r         <= '0;
            q_sum_r         <= '0;
            sample_count_r  <= '0;
            i_avg           <= '0;
            q_avg           <= '0;
            avg_valid       <= 1'b0;
            done_pulse      <= 1'b0;
            div_start_r     <= 1'b0;
        end else begin
            done_pulse  <= 1'b0;
            div_start_r <= 1'b0;

            if (clear) begin
                i_sum_r        <= '0;
                q_sum_r        <= '0;
                sample_count_r <= '0;
                i_avg          <= '0;
                q_avg          <= '0;
                avg_valid      <= 1'b0;
                state_r        <= CalStateIdle;
            end else begin
                if (push) begin
                    i_sum_r        <= i_sum_r + i_in;
                    q_sum_r        <= q_sum_r + q_in;
                    sample_count_r <= sample_count_r + 1'b1;
                    avg_valid      <= 1'b0;
                end

                case (state_r)
                    CalStateIdle: begin
                        if (finalize) begin
                            div_start_r <= 1'b1;
                            state_r     <= CalStateWaitDivI;
                        end
                    end

                    CalStateWaitDivI: begin
                        if (div_done) begin
                            i_avg       <= div_avg;
                            div_start_r <= 1'b1;
                            state_r     <= CalStateWaitDivQ;
                        end
                    end

                    CalStateWaitDivQ: begin
                        if (div_done) begin
                            q_avg      <= div_avg;
                            avg_valid  <= 1'b1;
                            done_pulse <= 1'b1;
                            state_r    <= CalStateIdle;
                        end
                    end

                    default: begin
                        state_r <= CalStateIdle;
                    end
                endcase
            end
        end
    end

    assign sample_count = sample_count_r;
    assign busy         = (state_r != CalStateIdle) || div_busy;

endmodule
