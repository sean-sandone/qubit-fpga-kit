//------------------------------------------------------------------------------
// PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
//------------------------------------------------------------------------------
// AUTHORS: Sean Sandone
// WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
//------------------------------------------------------------------------------

module register_bank (
    input  logic clk,
    input  logic rst_sync_n,

    // ============================================================
    // Control register write interface
    // ============================================================

    input  logic wr_control,
    input  logic control_start_exp_in,
    input  logic control_soft_reset_in,

    // ============================================================
    // Reset-wait register write interface
    // ============================================================

    input  logic        wr_reset_wait_cycles,
    input  logic [31:0] wr_reset_wait_cycles_data,

    // ============================================================
    // Play config memory write interface
    // ============================================================

    input  logic                          wr_play_cfg,
    input  logic [rtl_pkg::PlayCfgAw-1:0] wr_play_cfg_addr,
    input  rtl_pkg::play_cfg_t            wr_play_cfg_data,

    // ============================================================
    // Measure config memory write interface
    // ============================================================

    input  logic                          wr_measure_cfg,
    input  logic [rtl_pkg::MeasCfgAw-1:0] wr_measure_cfg_addr,
    input  rtl_pkg::measure_cfg_t         wr_measure_cfg_data,

    // ============================================================
    // Instruction memory write interface
    // ============================================================

    input  logic                          wr_instr,
    input  logic [rtl_pkg::InstrAw-1:0]   wr_instr_addr,
    input  rtl_pkg::instr_t               wr_instr_data,

    // ============================================================
    // Calibration result write interface
    // ============================================================

    input  logic        wr_cal_results,
    input  logic [1:0]  cal_store_sel_in,
    input  logic [15:0] cal_sample_count_in,
    input  logic signed [15:0] cal_i_avg_in,
    input  logic signed [15:0] cal_q_avg_in,

    // ============================================================
    // Measurement state update interface
    // ============================================================

    input  logic        clear_meas_state_valid,
    input  logic        wr_meas_state,
    input  logic signed [15:0] meas_i_avg_in,

    // ============================================================
    // Sequencer read interfaces
    // ============================================================

    input  logic [rtl_pkg::InstrAw-1:0]   rd_instr_addr,
    output rtl_pkg::instr_t               rd_instr_data,

    input  logic [rtl_pkg::PlayCfgAw-1:0] rd_play_cfg_addr,
    output rtl_pkg::play_cfg_t            rd_play_cfg_data,

    input  logic [rtl_pkg::MeasCfgAw-1:0] rd_measure_cfg_addr,
    output rtl_pkg::measure_cfg_t         rd_measure_cfg_data,

    // ============================================================
    // Sequencer / status handshake
    // ============================================================

    input  logic seq_busy_in,
    input  logic seq_done_pulse_in,
    input  logic clear_start_exp,

    // ============================================================
    // Control / status outputs
    // ============================================================

    output logic start_exp,
    output logic soft_reset_req,
    output logic [31:0] reset_wait_cycles,

    output logic play_cfg_any_valid,
    output logic measure_cfg_any_valid,
    output logic instr_any_valid,

    output logic seq_busy,
    output logic seq_done_sticky,

    output logic [15:0]        cal_sample_count,
    output logic signed [15:0] cal_i_avg,
    output logic signed [15:0] cal_q_avg,

    output logic signed [15:0] cal_i0_ref,
    output logic signed [15:0] cal_q0_ref,
    output logic signed [15:0] cal_i1_ref,
    output logic signed [15:0] cal_q1_ref,
    output logic signed [15:0] cal_i_threshold,
    output logic               cal_state_polarity,

    output logic cal_i0q0_valid,
    output logic cal_i1q1_valid,
    output logic cal_threshold_valid,

    output logic meas_state,
    output logic meas_state_valid,

    output logic cal_debug_update_pulse,
    output logic cal_debug_ref0_sel
);

    import rtl_pkg::*;

    // ============================================================
    // Memories
    // ============================================================

    play_cfg_t    play_cfg_mem_r [PlayCfgDepth];
    measure_cfg_t measure_cfg_mem_r [MeasCfgDepth];
    instr_t       instr_mem_r [InstrDepth];

    logic [PlayCfgDepth-1:0] play_cfg_valid_r;
    logic [MeasCfgDepth-1:0] measure_cfg_valid_r;
    logic [InstrDepth-1:0]   instr_valid_r;

    // ============================================================
    // Control / status registers
    // ============================================================

    logic        start_exp_r;
    logic        soft_reset_req_r;
    logic        seq_done_sticky_r;
    logic [31:0] reset_wait_cycles_r;

    logic [15:0]        cal_sample_count_r;
    logic signed [15:0] cal_i_avg_r;
    logic signed [15:0] cal_q_avg_r;

    logic signed [15:0] reg_cal_i0_ref_r;
    logic signed [15:0] reg_cal_q0_ref_r;
    logic signed [15:0] reg_cal_i1_ref_r;
    logic signed [15:0] reg_cal_q1_ref_r;
    logic signed [15:0] reg_cal_i_threshold_r;
    logic               reg_cal_state_polarity_r;

    logic reg_cal_i0q0_valid_r;
    logic reg_cal_i1q1_valid_r;
    logic reg_cal_threshold_valid_r;
    logic reg_meas_state_r;
    logic reg_meas_state_valid_r;
    logic cal_debug_update_pulse_r;
    logic cal_debug_ref0_sel_r;

    // ============================================================
    // Read data registers
    // ============================================================

    play_cfg_t    rd_play_cfg_data_r;
    measure_cfg_t rd_measure_cfg_data_r;
    instr_t       rd_instr_data_r;

    integer i;

    // ============================================================
    // Sequential logic
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
            start_exp_r               <= 1'b0;
            soft_reset_req_r          <= 1'b0;
            seq_done_sticky_r         <= 1'b0;
            reset_wait_cycles_r       <= 32'd0;

            cal_sample_count_r        <= 16'd0;
            cal_i_avg_r               <= '0;
            cal_q_avg_r               <= '0;

            reg_cal_i0_ref_r          <= '0;
            reg_cal_q0_ref_r          <= '0;
            reg_cal_i1_ref_r          <= '0;
            reg_cal_q1_ref_r          <= '0;
            reg_cal_i_threshold_r     <= '0;
            reg_cal_state_polarity_r  <= 1'b0;

            reg_cal_i0q0_valid_r      <= 1'b0;
            reg_cal_i1q1_valid_r      <= 1'b0;
            reg_cal_threshold_valid_r <= 1'b0;
            reg_meas_state_r          <= 1'b0;
            reg_meas_state_valid_r    <= 1'b0;
            cal_debug_update_pulse_r  <= 1'b0;
            cal_debug_ref0_sel_r      <= 1'b0;

            for (i = 0; i < PlayCfgDepth; i = i + 1) begin
                play_cfg_mem_r[i]   <= '0;
                play_cfg_valid_r[i] <= 1'b0;
            end

            for (i = 0; i < MeasCfgDepth; i = i + 1) begin
                measure_cfg_mem_r[i]   <= '0;
                measure_cfg_valid_r[i] <= 1'b0;
            end

            for (i = 0; i < InstrDepth; i = i + 1) begin
                instr_mem_r[i]   <= '0;
                instr_valid_r[i] <= 1'b0;
            end
        end else begin
            soft_reset_req_r         <= 1'b0;
            cal_debug_update_pulse_r <= 1'b0;

            if (wr_control) begin
                if (control_start_exp_in) begin
                    start_exp_r       <= 1'b1;
                    seq_done_sticky_r <= 1'b0;
                end

                if (control_soft_reset_in) begin
                    soft_reset_req_r <= 1'b1;
                end
            end

            if (wr_reset_wait_cycles) begin
                reset_wait_cycles_r <= wr_reset_wait_cycles_data;
            end

            if (clear_start_exp) begin
                start_exp_r <= 1'b0;
            end

            if (wr_play_cfg) begin
                play_cfg_mem_r[wr_play_cfg_addr]   <= wr_play_cfg_data;
                play_cfg_valid_r[wr_play_cfg_addr] <= 1'b1;
            end

            if (wr_measure_cfg) begin
                measure_cfg_mem_r[wr_measure_cfg_addr]   <= wr_measure_cfg_data;
                measure_cfg_valid_r[wr_measure_cfg_addr] <= 1'b1;
            end

            if (wr_instr) begin
                instr_mem_r[wr_instr_addr]   <= wr_instr_data;
                instr_valid_r[wr_instr_addr] <= 1'b1;
            end

            if (clear_meas_state_valid) begin
                reg_meas_state_valid_r <= 1'b0;
            end

            if (wr_meas_state) begin
                if (reg_cal_threshold_valid_r) begin
                    if (reg_cal_state_polarity_r) begin
                        reg_meas_state_r <= (meas_i_avg_in >= reg_cal_i_threshold_r);
                    end else begin
                        reg_meas_state_r <= (meas_i_avg_in < reg_cal_i_threshold_r);
                    end

                    reg_meas_state_valid_r <= 1'b1;
                end else begin
                    reg_meas_state_valid_r <= 1'b0;
                end
            end

            if (wr_cal_results) begin
                cal_sample_count_r <= cal_sample_count_in;
                cal_i_avg_r        <= cal_i_avg_in;
                cal_q_avg_r        <= cal_q_avg_in;

                unique case (cal_store_sel_in)
                    CAL_DEST_REF0: begin
                        reg_cal_i0_ref_r     <= cal_i_avg_in;
                        reg_cal_q0_ref_r     <= cal_q_avg_in;
                        reg_cal_i0q0_valid_r <= 1'b1;
                        cal_debug_ref0_sel_r <= 1'b1;

                        if (reg_cal_i1q1_valid_r) begin
                            reg_cal_i_threshold_r     <= (cal_i_avg_in + reg_cal_i1_ref_r) >>> 1;
                            reg_cal_state_polarity_r  <= (reg_cal_i1_ref_r >= cal_i_avg_in);
                            reg_cal_threshold_valid_r <= 1'b1;
                        end

                        cal_debug_update_pulse_r <= 1'b1;
                    end

                    CAL_DEST_REF1: begin
                        reg_cal_i1_ref_r     <= cal_i_avg_in;
                        reg_cal_q1_ref_r     <= cal_q_avg_in;
                        reg_cal_i1q1_valid_r <= 1'b1;
                        cal_debug_ref0_sel_r <= 1'b0;

                        if (reg_cal_i0q0_valid_r) begin
                            reg_cal_i_threshold_r     <= (reg_cal_i0_ref_r + cal_i_avg_in) >>> 1;
                            reg_cal_state_polarity_r  <= (cal_i_avg_in >= reg_cal_i0_ref_r);
                            reg_cal_threshold_valid_r <= 1'b1;
                        end

                        cal_debug_update_pulse_r <= 1'b1;
                    end

                    default: begin
                    end
                endcase
            end

            if (seq_done_pulse_in) begin
                seq_done_sticky_r <= 1'b1;
            end
        end
    end

    // ============================================================
    // Read ports
    // Combinational for now, fine for a small starter design
    // Can be changed to synchronous BRAM-style later
    // ============================================================

    always_comb begin
        rd_instr_data_r       = instr_mem_r[rd_instr_addr];
        rd_play_cfg_data_r    = play_cfg_mem_r[rd_play_cfg_addr];
        rd_measure_cfg_data_r = measure_cfg_mem_r[rd_measure_cfg_addr];
    end

    // ============================================================
    // Outputs
    // ============================================================

    assign rd_instr_data       = rd_instr_data_r;
    assign rd_play_cfg_data    = rd_play_cfg_data_r;
    assign rd_measure_cfg_data = rd_measure_cfg_data_r;

    assign start_exp         = start_exp_r;
    assign soft_reset_req    = soft_reset_req_r;
    assign reset_wait_cycles = reset_wait_cycles_r;

    assign play_cfg_any_valid    = |play_cfg_valid_r;
    assign measure_cfg_any_valid = |measure_cfg_valid_r;
    assign instr_any_valid       = |instr_valid_r;

    assign seq_busy        = seq_busy_in;
    assign seq_done_sticky = seq_done_sticky_r;

    assign cal_sample_count = cal_sample_count_r;
    assign cal_i_avg        = cal_i_avg_r;
    assign cal_q_avg        = cal_q_avg_r;

    assign cal_i0_ref         = reg_cal_i0_ref_r;
    assign cal_q0_ref         = reg_cal_q0_ref_r;
    assign cal_i1_ref         = reg_cal_i1_ref_r;
    assign cal_q1_ref         = reg_cal_q1_ref_r;
    assign cal_i_threshold    = reg_cal_i_threshold_r;
    assign cal_state_polarity = reg_cal_state_polarity_r;

    assign cal_i0q0_valid      = reg_cal_i0q0_valid_r;
    assign cal_i1q1_valid      = reg_cal_i1q1_valid_r;
    assign cal_threshold_valid = reg_cal_threshold_valid_r;

    assign meas_state       = reg_meas_state_r;
    assign meas_state_valid = reg_meas_state_valid_r;

    assign cal_debug_update_pulse = cal_debug_update_pulse_r;
    assign cal_debug_ref0_sel     = cal_debug_ref0_sel_r;

endmodule
