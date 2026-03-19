//------------------------------------------------------------------------------
// PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
//------------------------------------------------------------------------------
// AUTHORS: Sean Sandone
// WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
//------------------------------------------------------------------------------

module debug_ctrl (
    input  logic clk,
    input  logic rst_sync_n,

    input  logic reg_cal_debug_update_pulse,
    input  logic measure_rsp_done_pulse,
    input  logic debug_start,

    input  logic cal_debug_ref0_sel,

    input  logic signed [15:0] reg_cal_i0_ref,
    input  logic signed [15:0] reg_cal_q0_ref,
    input  logic signed [15:0] reg_cal_i1_ref,
    input  logic signed [15:0] reg_cal_q1_ref,
    input  logic signed [15:0] measure_i_avg,
    input  logic signed [15:0] measure_q_avg,

    output logic               debug_pending,
    output logic               debug_pending_is_cal,
    output logic signed [15:0] debug_i_avg_sel,
    output logic signed [15:0] debug_q_avg_sel
);

    // ============================================================
    // Latch debug requests until UART ownership is available
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
            debug_pending        <= 1'b0;
            debug_pending_is_cal <= 1'b0;
        end else begin
            if (reg_cal_debug_update_pulse) begin
                debug_pending        <= 1'b1;
                debug_pending_is_cal <= 1'b1;
            end else if (measure_rsp_done_pulse) begin
                debug_pending        <= 1'b1;
                debug_pending_is_cal <= 1'b0;
            end else if (debug_start) begin
                debug_pending        <= 1'b0;
                debug_pending_is_cal <= 1'b0;
            end
        end
    end

    always_comb begin
        if (debug_pending_is_cal) begin
            if (cal_debug_ref0_sel) begin
                debug_i_avg_sel = reg_cal_i0_ref;
                debug_q_avg_sel = reg_cal_q0_ref;
            end else begin
                debug_i_avg_sel = reg_cal_i1_ref;
                debug_q_avg_sel = reg_cal_q1_ref;
            end
        end else begin
            debug_i_avg_sel = measure_i_avg;
            debug_q_avg_sel = measure_q_avg;
        end
    end

endmodule
