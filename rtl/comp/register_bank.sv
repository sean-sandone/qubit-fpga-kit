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
    output logic seq_done_sticky
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
            start_exp_r         <= 1'b0;
            soft_reset_req_r    <= 1'b0;
            seq_done_sticky_r   <= 1'b0;
            reset_wait_cycles_r <= 32'd0;

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
            soft_reset_req_r <= 1'b0;

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

endmodule
