//------------------------------------------------------------------------------
// PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
//------------------------------------------------------------------------------
// AUTHORS: Sean Sandone
// WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
//------------------------------------------------------------------------------

module write_reg_arbiter (
    input  logic clk,
    input  logic rst_sync_n,

    input  logic                          init_wr_control,
    input  logic                          init_control_start_exp,
    input  logic                          init_control_soft_reset,

    input  logic                          init_wr_reset_wait_cycles,
    input  logic [31:0]                   init_wr_reset_wait_cycles_data,

    input  logic                          init_wr_play_cfg,
    input  logic [rtl_pkg::PlayCfgAw-1:0] init_wr_play_cfg_addr,
    input  rtl_pkg::play_cfg_t            init_wr_play_cfg_data,

    input  logic                          init_wr_measure_cfg,
    input  logic [rtl_pkg::MeasCfgAw-1:0] init_wr_measure_cfg_addr,
    input  rtl_pkg::measure_cfg_t         init_wr_measure_cfg_data,

    input  logic                          init_wr_instr,
    input  logic [rtl_pkg::InstrAw-1:0]   init_wr_instr_addr,
    input  rtl_pkg::instr_t               init_wr_instr_data,

    input  logic                          uart_req_valid,
    output logic                          uart_req_accept,
    input  rtl_pkg::reg_wr_kind_t         uart_req_kind,

    input  logic                          uart_control_start_exp,
    input  logic                          uart_control_soft_reset,
    input  logic [31:0]                   uart_reset_wait_cycles_data,

    input  logic [rtl_pkg::PlayCfgAw-1:0] uart_play_cfg_addr,
    input  rtl_pkg::play_cfg_t            uart_play_cfg_data,

    input  logic [rtl_pkg::MeasCfgAw-1:0] uart_measure_cfg_addr,
    input  rtl_pkg::measure_cfg_t         uart_measure_cfg_data,

    input  logic [rtl_pkg::InstrAw-1:0]   uart_instr_addr,
    input  rtl_pkg::instr_t               uart_instr_data,

    output logic                          arb_wr_control,
    output logic                          arb_control_start_exp,
    output logic                          arb_control_soft_reset,

    output logic                          arb_wr_reset_wait_cycles,
    output logic [31:0]                   arb_wr_reset_wait_cycles_data,

    output logic                          arb_wr_play_cfg,
    output logic [rtl_pkg::PlayCfgAw-1:0] arb_wr_play_cfg_addr,
    output rtl_pkg::play_cfg_t            arb_wr_play_cfg_data,

    output logic                          arb_wr_measure_cfg,
    output logic [rtl_pkg::MeasCfgAw-1:0] arb_wr_measure_cfg_addr,
    output rtl_pkg::measure_cfg_t         arb_wr_measure_cfg_data,

    output logic                          arb_wr_instr,
    output logic [rtl_pkg::InstrAw-1:0]   arb_wr_instr_addr,
    output rtl_pkg::instr_t               arb_wr_instr_data
);

    import rtl_pkg::*;

    always_comb begin
        arb_wr_control                = 1'b0;
        arb_control_start_exp         = 1'b0;
        arb_control_soft_reset        = 1'b0;

        arb_wr_reset_wait_cycles      = 1'b0;
        arb_wr_reset_wait_cycles_data = '0;

        arb_wr_play_cfg               = 1'b0;
        arb_wr_play_cfg_addr          = '0;
        arb_wr_play_cfg_data          = '0;

        arb_wr_measure_cfg            = 1'b0;
        arb_wr_measure_cfg_addr       = '0;
        arb_wr_measure_cfg_data       = '0;

        arb_wr_instr                  = 1'b0;
        arb_wr_instr_addr             = '0;
        arb_wr_instr_data             = '0;

        uart_req_accept               = 1'b0;

        if (init_wr_control || init_wr_reset_wait_cycles || init_wr_play_cfg ||
            init_wr_measure_cfg || init_wr_instr) begin

            arb_wr_control                = init_wr_control;
            arb_control_start_exp         = init_control_start_exp;
            arb_control_soft_reset        = init_control_soft_reset;

            arb_wr_reset_wait_cycles      = init_wr_reset_wait_cycles;
            arb_wr_reset_wait_cycles_data = init_wr_reset_wait_cycles_data;

            arb_wr_play_cfg               = init_wr_play_cfg;
            arb_wr_play_cfg_addr          = init_wr_play_cfg_addr;
            arb_wr_play_cfg_data          = init_wr_play_cfg_data;

            arb_wr_measure_cfg            = init_wr_measure_cfg;
            arb_wr_measure_cfg_addr       = init_wr_measure_cfg_addr;
            arb_wr_measure_cfg_data       = init_wr_measure_cfg_data;

            arb_wr_instr                  = init_wr_instr;
            arb_wr_instr_addr             = init_wr_instr_addr;
            arb_wr_instr_data             = init_wr_instr_data;

        end else if (uart_req_valid) begin
            uart_req_accept = 1'b1;

            unique case (uart_req_kind)
                REG_WR_KIND_CONTROL: begin
                    arb_wr_control         = 1'b1;
                    arb_control_start_exp  = uart_control_start_exp;
                    arb_control_soft_reset = uart_control_soft_reset;
                end

                REG_WR_KIND_RESET_WAIT: begin
                    arb_wr_reset_wait_cycles      = 1'b1;
                    arb_wr_reset_wait_cycles_data = uart_reset_wait_cycles_data;
                end

                REG_WR_KIND_PLAY_CFG: begin
                    arb_wr_play_cfg      = 1'b1;
                    arb_wr_play_cfg_addr = uart_play_cfg_addr;
                    arb_wr_play_cfg_data = uart_play_cfg_data;
                end

                REG_WR_KIND_MEASURE_CFG: begin
                    arb_wr_measure_cfg      = 1'b1;
                    arb_wr_measure_cfg_addr = uart_measure_cfg_addr;
                    arb_wr_measure_cfg_data = uart_measure_cfg_data;
                end

                REG_WR_KIND_INSTR: begin
                    arb_wr_instr      = 1'b1;
                    arb_wr_instr_addr = uart_instr_addr;
                    arb_wr_instr_data = uart_instr_data;
                end

                default: begin
                    uart_req_accept = 1'b0;
                end
            endcase
        end
    end

endmodule
