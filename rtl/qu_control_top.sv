//------------------------------------------------------------------------------
// PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
//------------------------------------------------------------------------------
// AUTHORS: Sean Sandone
// WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
//------------------------------------------------------------------------------

module qu_control_top #(  // Xilinx KCU105 Eval Board
    parameter int CLK_FREQ_HZ = 125_000_000,
    parameter int BAUD_RATE   = 115200,
    parameter int unsigned STEP_HZ = 5  // used for led blink timing
)(
    input  logic clk_125mhz_p,
    input  logic clk_125mhz_n,

    input  logic USB_UART_TX,  // labeled from the perspective of the USB UART transceiver chip
    output logic USB_UART_RX,  // labeled from the perspective of the USB UART transceiver chip

    input  logic CPU_RESET,  // active high async reset (input)

    output logic GPIO_LED_0_LS,
    output logic GPIO_LED_1_LS,
    output logic GPIO_LED_2_LS,
    output logic GPIO_LED_3_LS,
    output logic GPIO_LED_4_LS,
    output logic GPIO_LED_5_LS,
    output logic GPIO_LED_6_LS,
    output logic GPIO_LED_7_LS
);

    import rtl_pkg::*;

    // ============================================================
    // Clocking
    // ============================================================

    logic clk;

    IBUFDS u_ibufds_clk125 (
        .I  (clk_125mhz_p),
        .IB (clk_125mhz_n),
        .O  (clk)
    );

    // ============================================================
    // Reset synchronizer
    // CPU_RESET is active-high on the board
    // Internal reset is active-low for the design
    // ============================================================

    logic rst_sync;
    logic rst_sync_n;
    // Vivado synth attributes to prevent optimization of synchronizer flip-flops
    (* ASYNC_REG = "TRUE", KEEP = "TRUE" *) logic rst_ff1_n;
    (* ASYNC_REG = "TRUE", KEEP = "TRUE" *) logic rst_ff2_n;

    always_ff @(posedge clk or posedge CPU_RESET) begin
        if (CPU_RESET) begin
            rst_ff1_n <= 1'b0;
            rst_ff2_n <= 1'b0;
        end else begin
            rst_ff1_n <= 1'b1;
            rst_ff2_n <= rst_ff1_n;
        end
    end

    assign rst_sync_n = rst_ff2_n;
    assign rst_sync   = !rst_ff2_n;

    // ============================================================
    // UART monitor/debug signals
    // ============================================================

    logic uart_txd_mon;
    logic uart_rxd_mon;

    logic [7:0] uart_dout;
    logic       uart_dout_vld;
    logic       frame_error;
    logic       parity_error;

    logic [7:0] uart_tx_data;
    logic       uart_tx_valid;
    logic       uart_tx_ready;

    // ============================================================
    // UART frontend
    // ============================================================

    uart_wrapper #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE)
    ) u_uart_wrapper (
        .clk             (clk),
        .rst_sync        (rst_sync),
        .rst_sync_n      (rst_sync_n),

        .usb_uart_tx_in  (USB_UART_TX),
        .usb_uart_rx_out (USB_UART_RX),

        .uart_txd_mon    (uart_txd_mon),
        .uart_rxd_mon    (uart_rxd_mon),

        .tx_data         (uart_tx_data),
        .tx_valid        (uart_tx_valid),
        .tx_ready        (uart_tx_ready),

        .dout_vld        (uart_dout_vld),
        .frame_error     (frame_error),
        .parity_error    (parity_error),
        .dout            (uart_dout)
    );

    // ============================================================
    // LED engine
    // ============================================================

    leds #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .STEP_HZ    (STEP_HZ)
    ) u_leds (
        .clk           (clk),
        .rst_sync_n    (rst_sync_n),

        .uart_txd_mon  (uart_txd_mon),
        .uart_rxd_mon  (uart_rxd_mon),

        .GPIO_LED_0_LS (GPIO_LED_0_LS),
        .GPIO_LED_1_LS (GPIO_LED_1_LS),
        .GPIO_LED_2_LS (GPIO_LED_2_LS),
        .GPIO_LED_3_LS (GPIO_LED_3_LS),
        .GPIO_LED_4_LS (GPIO_LED_4_LS),
        .GPIO_LED_5_LS (GPIO_LED_5_LS),
        .GPIO_LED_6_LS (GPIO_LED_6_LS),
        .GPIO_LED_7_LS (GPIO_LED_7_LS)
    );

    // ============================================================
    // Defaults ROM / init loader
    // ============================================================

    logic [InitRomAw-1:0] init_rom_addr;
    init_rom_word_t       init_rom_word;

    logic                 init_wr_control;
    logic                 init_control_start_exp;
    logic                 init_control_soft_reset;

    logic                 init_wr_reset_wait_cycles;
    logic [31:0]          init_wr_reset_wait_cycles_data;

    logic                 init_wr_play_cfg;
    logic [PlayCfgAw-1:0] init_wr_play_cfg_addr;
    play_cfg_t            init_wr_play_cfg_data;

    logic                 init_wr_measure_cfg;
    logic [MeasCfgAw-1:0] init_wr_measure_cfg_addr;
    measure_cfg_t         init_wr_measure_cfg_data;

    logic                 init_wr_instr;
    logic [InstrAw-1:0]   init_wr_instr_addr;
    instr_t               init_wr_instr_data;

    logic                 init_active;
    logic                 init_done;

    defaults_rom u_defaults_rom (
        .rom_addr (init_rom_addr),
        .rom_word (init_rom_word)
    );

    init_loader u_init_loader (
        .clk                   (clk),
        .rst_sync_n            (rst_sync_n),

        .rom_addr              (init_rom_addr),
        .rom_word              (init_rom_word),

        .wr_control            (init_wr_control),
        .control_start_exp_in  (init_control_start_exp),
        .control_soft_reset_in (init_control_soft_reset),

        .wr_reset_wait_cycles      (init_wr_reset_wait_cycles),
        .wr_reset_wait_cycles_data (init_wr_reset_wait_cycles_data),

        .wr_play_cfg           (init_wr_play_cfg),
        .wr_play_cfg_addr      (init_wr_play_cfg_addr),
        .wr_play_cfg_data      (init_wr_play_cfg_data),

        .wr_measure_cfg        (init_wr_measure_cfg),
        .wr_measure_cfg_addr   (init_wr_measure_cfg_addr),
        .wr_measure_cfg_data   (init_wr_measure_cfg_data),

        .wr_instr              (init_wr_instr),
        .wr_instr_addr         (init_wr_instr_addr),
        .wr_instr_data         (init_wr_instr_data),

        .init_active           (init_active),
        .init_done             (init_done)
    );

    // ============================================================
    // Register bank read side
    // ============================================================

    logic [InstrAw-1:0]   rd_instr_addr;
    instr_t               rd_instr_data;

    logic [PlayCfgAw-1:0] rd_play_cfg_addr;
    play_cfg_t            rd_play_cfg_data;

    logic [MeasCfgAw-1:0] rd_measure_cfg_addr;
    measure_cfg_t         rd_measure_cfg_data;

    // ============================================================
    // Register bank status / control
    // ============================================================

    logic        start_exp;
    logic        soft_reset_req;
    logic [31:0] reset_wait_cycles;

    logic play_cfg_any_valid;
    logic measure_cfg_any_valid;
    logic instr_any_valid;

    logic seq_busy;
    logic seq_done_sticky;

    logic seq_done_pulse_in;
    logic clear_start_exp;

    // ============================================================
    // Calibration results / registers
    // ============================================================

    logic        cal_accum_clear;
    logic        cal_accum_push;
    logic        cal_accum_finalize;
    logic [1:0]  cal_accum_store_sel;
    logic        cal_accum_busy;
    logic        cal_accum_done_pulse;
    logic        cal_accum_avg_valid;
    logic [15:0] cal_accum_sample_count;
    logic signed [15:0] cal_accum_i_avg;
    logic signed [15:0] cal_accum_q_avg;

    logic [15:0]        reg_cal_sample_count;
    logic signed [15:0] reg_cal_i_avg;
    logic signed [15:0] reg_cal_q_avg;

    logic signed [15:0] reg_cal_i0_ref;
    logic signed [15:0] reg_cal_q0_ref;
    logic signed [15:0] reg_cal_i1_ref;
    logic signed [15:0] reg_cal_q1_ref;
    logic signed [15:0] reg_cal_i_threshold;
    logic               reg_cal_state_polarity;

    logic reg_cal_i0q0_valid;
    logic reg_cal_i1q1_valid;
    logic reg_cal_threshold_valid;
    logic reg_meas_state;
    logic reg_meas_state_valid;
    logic reg_cal_debug_update_pulse;
    logic reg_cal_debug_ref0_sel;

    logic clear_meas_state_valid;
    logic measure_start;

    // ============================================================
    // Register write arbitration
    // ============================================================

    logic                 arb_wr_control;
    logic                 arb_control_start_exp;
    logic                 arb_control_soft_reset;

    logic                 arb_wr_reset_wait_cycles;
    logic [31:0]          arb_wr_reset_wait_cycles_data;

    logic                 arb_wr_play_cfg;
    logic [PlayCfgAw-1:0] arb_wr_play_cfg_addr;
    play_cfg_t            arb_wr_play_cfg_data;

    logic                 arb_wr_measure_cfg;
    logic [MeasCfgAw-1:0] arb_wr_measure_cfg_addr;
    measure_cfg_t         arb_wr_measure_cfg_data;

    logic                 arb_wr_instr;
    logic [InstrAw-1:0]   arb_wr_instr_addr;
    instr_t               arb_wr_instr_data;

    logic                 uart_reg_wr_req_valid;
    logic                 uart_reg_wr_req_accept;
    reg_wr_kind_t         uart_reg_wr_req_kind;
    logic                 uart_reg_wr_control_start_exp;
    logic                 uart_reg_wr_control_soft_reset;
    logic [31:0]          uart_reg_wr_reset_wait_cycles_data;
    logic [PlayCfgAw-1:0] uart_reg_wr_play_cfg_addr;
    play_cfg_t            uart_reg_wr_play_cfg_data;
    logic [MeasCfgAw-1:0] uart_reg_wr_measure_cfg_addr;
    measure_cfg_t         uart_reg_wr_measure_cfg_data;
    logic [InstrAw-1:0]   uart_reg_wr_instr_addr;
    instr_t               uart_reg_wr_instr_data;

    assign clear_start_exp        = 1'b0;
    assign clear_meas_state_valid = measure_start;

    // ============================================================
    // Register bank
    // ============================================================

    register_bank u_register_bank (
        .clk                   (clk),
        .rst_sync_n            (rst_sync_n),

        .wr_control            (arb_wr_control),
        .control_start_exp_in  (arb_control_start_exp),
        .control_soft_reset_in (arb_control_soft_reset),

        .wr_reset_wait_cycles      (arb_wr_reset_wait_cycles),
        .wr_reset_wait_cycles_data (arb_wr_reset_wait_cycles_data),

        .wr_play_cfg           (arb_wr_play_cfg),
        .wr_play_cfg_addr      (arb_wr_play_cfg_addr),
        .wr_play_cfg_data      (arb_wr_play_cfg_data),

        .wr_measure_cfg        (arb_wr_measure_cfg),
        .wr_measure_cfg_addr   (arb_wr_measure_cfg_addr),
        .wr_measure_cfg_data   (arb_wr_measure_cfg_data),

        .wr_instr              (arb_wr_instr),
        .wr_instr_addr         (arb_wr_instr_addr),
        .wr_instr_data         (arb_wr_instr_data),

        .wr_cal_results        (cal_accum_done_pulse),
        .cal_store_sel_in      (cal_accum_store_sel),
        .cal_sample_count_in   (cal_accum_sample_count),
        .cal_i_avg_in          (cal_accum_i_avg),
        .cal_q_avg_in          (cal_accum_q_avg),

        .clear_meas_state_valid(clear_meas_state_valid),
        .wr_meas_state         (measure_rsp_done_pulse),
        .meas_i_avg_in         (measure_i_avg),

        .rd_instr_addr         (rd_instr_addr),
        .rd_instr_data         (rd_instr_data),

        .rd_play_cfg_addr      (rd_play_cfg_addr),
        .rd_play_cfg_data      (rd_play_cfg_data),

        .rd_measure_cfg_addr   (rd_measure_cfg_addr),
        .rd_measure_cfg_data   (rd_measure_cfg_data),

        .seq_busy_in           (seq_busy),
        .seq_done_pulse_in     (seq_done_pulse_in),
        .clear_start_exp       (clear_start_exp),

        .start_exp             (start_exp),
        .soft_reset_req        (soft_reset_req),
        .reset_wait_cycles     (reset_wait_cycles),

        .play_cfg_any_valid    (play_cfg_any_valid),
        .measure_cfg_any_valid (measure_cfg_any_valid),
        .instr_any_valid       (instr_any_valid),

        .seq_busy              (seq_busy),
        .seq_done_sticky       (seq_done_sticky),

        .cal_sample_count      (reg_cal_sample_count),
        .cal_i_avg             (reg_cal_i_avg),
        .cal_q_avg             (reg_cal_q_avg),

        .cal_i0_ref            (reg_cal_i0_ref),
        .cal_q0_ref            (reg_cal_q0_ref),
        .cal_i1_ref            (reg_cal_i1_ref),
        .cal_q1_ref            (reg_cal_q1_ref),
        .cal_i_threshold       (reg_cal_i_threshold),
        .cal_state_polarity    (reg_cal_state_polarity),

        .cal_i0q0_valid        (reg_cal_i0q0_valid),
        .cal_i1q1_valid        (reg_cal_i1q1_valid),
        .cal_threshold_valid   (reg_cal_threshold_valid),

        .meas_state            (reg_meas_state),
        .meas_state_valid      (reg_meas_state_valid),

        .cal_debug_update_pulse(reg_cal_debug_update_pulse),
        .cal_debug_ref0_sel    (reg_cal_debug_ref0_sel)
    );

    // ============================================================
    // UART register write receiver
    // ============================================================

    write_reg_rx u_write_reg_rx (
        .clk                    (clk),
        .rst_sync_n             (rst_sync_n),
        .enable                 (init_done),

        .rx_byte_valid          (uart_dout_vld),
        .rx_byte                (uart_dout),

        .req_valid              (uart_reg_wr_req_valid),
        .req_accept             (uart_reg_wr_req_accept),
        .req_kind               (uart_reg_wr_req_kind),

        .control_start_exp      (uart_reg_wr_control_start_exp),
        .control_soft_reset     (uart_reg_wr_control_soft_reset),
        .reset_wait_cycles_data (uart_reg_wr_reset_wait_cycles_data),

        .play_cfg_addr          (uart_reg_wr_play_cfg_addr),
        .play_cfg_data          (uart_reg_wr_play_cfg_data),

        .measure_cfg_addr       (uart_reg_wr_measure_cfg_addr),
        .measure_cfg_data       (uart_reg_wr_measure_cfg_data),

        .instr_addr             (uart_reg_wr_instr_addr),
        .instr_data             (uart_reg_wr_instr_data)
    );

    // ============================================================
    // Register write arbitration
    // ============================================================

    write_reg_arbiter u_write_reg_arbiter (
        .clk                         (clk),
        .rst_sync_n                  (rst_sync_n),

        .init_wr_control             (init_wr_control),
        .init_control_start_exp      (init_control_start_exp),
        .init_control_soft_reset     (init_control_soft_reset),

        .init_wr_reset_wait_cycles   (init_wr_reset_wait_cycles),
        .init_wr_reset_wait_cycles_data(init_wr_reset_wait_cycles_data),

        .init_wr_play_cfg            (init_wr_play_cfg),
        .init_wr_play_cfg_addr       (init_wr_play_cfg_addr),
        .init_wr_play_cfg_data       (init_wr_play_cfg_data),

        .init_wr_measure_cfg         (init_wr_measure_cfg),
        .init_wr_measure_cfg_addr    (init_wr_measure_cfg_addr),
        .init_wr_measure_cfg_data    (init_wr_measure_cfg_data),

        .init_wr_instr               (init_wr_instr),
        .init_wr_instr_addr          (init_wr_instr_addr),
        .init_wr_instr_data          (init_wr_instr_data),

        .uart_req_valid              (uart_reg_wr_req_valid),
        .uart_req_accept             (uart_reg_wr_req_accept),
        .uart_req_kind               (uart_reg_wr_req_kind),

        .uart_control_start_exp      (uart_reg_wr_control_start_exp),
        .uart_control_soft_reset     (uart_reg_wr_control_soft_reset),
        .uart_reset_wait_cycles_data (uart_reg_wr_reset_wait_cycles_data),

        .uart_play_cfg_addr          (uart_reg_wr_play_cfg_addr),
        .uart_play_cfg_data          (uart_reg_wr_play_cfg_data),

        .uart_measure_cfg_addr       (uart_reg_wr_measure_cfg_addr),
        .uart_measure_cfg_data       (uart_reg_wr_measure_cfg_data),

        .uart_instr_addr             (uart_reg_wr_instr_addr),
        .uart_instr_data             (uart_reg_wr_instr_data),

        .arb_wr_control              (arb_wr_control),
        .arb_control_start_exp       (arb_control_start_exp),
        .arb_control_soft_reset      (arb_control_soft_reset),

        .arb_wr_reset_wait_cycles    (arb_wr_reset_wait_cycles),
        .arb_wr_reset_wait_cycles_data(arb_wr_reset_wait_cycles_data),

        .arb_wr_play_cfg             (arb_wr_play_cfg),
        .arb_wr_play_cfg_addr        (arb_wr_play_cfg_addr),
        .arb_wr_play_cfg_data        (arb_wr_play_cfg_data),

        .arb_wr_measure_cfg          (arb_wr_measure_cfg),
        .arb_wr_measure_cfg_addr     (arb_wr_measure_cfg_addr),
        .arb_wr_measure_cfg_data     (arb_wr_measure_cfg_data),

        .arb_wr_instr                (arb_wr_instr),
        .arb_wr_instr_addr           (arb_wr_instr_addr),
        .arb_wr_instr_data           (arb_wr_instr_data)
    );

    // ============================================================
    // Sequencer -> formatter path
    // ============================================================

    logic                 formatter_start;
    logic                 formatter_is_play;
    logic                 formatter_is_reset;
    logic [3:0]           formatter_cfg_index;
    play_cfg_t            formatter_play_cfg;
    measure_cfg_t         formatter_measure_cfg;
    logic                 formatter_busy;
    logic                 formatter_done_pulse;

    // ============================================================
    // Formatter UART source
    // ============================================================

    logic [7:0] formatter_tx_data;
    logic       formatter_tx_valid;
    logic       formatter_tx_ready;

    // ============================================================
    // Measure response RX / processing
    // ============================================================

    logic               measure_rsp_busy;
    logic               measure_rsp_done_pulse;
    logic               measure_rsp_valid;
    logic [7:0]         measure_rsp_sample_count;
    logic signed [15:0] measure_i_avg;
    logic signed [15:0] measure_q_avg;

    // ============================================================
    // Debug UART source
    // ============================================================

    logic               debug_start;
    logic [7:0]         debug_tx_data;
    logic               debug_tx_valid;
    logic               debug_tx_ready;
    logic               debug_busy;
    logic               debug_done_pulse;
    logic               debug_pending;
    logic               debug_pending_is_cal;
    logic signed [15:0] debug_i_avg_sel;
    logic signed [15:0] debug_q_avg_sel;

    // ============================================================
    // Latch debug requests until UART ownership is available
    // Mux between calibration data and measurement data for debug
    // ============================================================

    debug_ctrl u_debug_ctrl (
        .clk                        (clk),
        .rst_sync_n                 (rst_sync_n),
        .reg_cal_debug_update_pulse (reg_cal_debug_update_pulse),
        .measure_rsp_done_pulse     (measure_rsp_done_pulse),
        .debug_start                (debug_start),

        .cal_debug_ref0_sel         (reg_cal_debug_ref0_sel),

        .reg_cal_i0_ref             (reg_cal_i0_ref),
        .reg_cal_q0_ref             (reg_cal_q0_ref),
        .reg_cal_i1_ref             (reg_cal_i1_ref),
        .reg_cal_q1_ref             (reg_cal_q1_ref),
        .measure_i_avg              (measure_i_avg),
        .measure_q_avg              (measure_q_avg),

        .debug_pending              (debug_pending),
        .debug_pending_is_cal       (debug_pending_is_cal),
        .debug_i_avg_sel            (debug_i_avg_sel),
        .debug_q_avg_sel            (debug_q_avg_sel)
    );

    // ============================================================
    // UART TX arbitration
    // ============================================================

    tx_arbiter u_tx_arbiter (
        .clk                 (clk),
        .rst_sync_n          (rst_sync_n),

        .formatter_tx_data   (formatter_tx_data),
        .formatter_tx_valid  (formatter_tx_valid),
        .formatter_tx_ready  (formatter_tx_ready),
        .formatter_busy      (formatter_busy),
        .formatter_done_pulse(formatter_done_pulse),

        .debug_tx_data       (debug_tx_data),
        .debug_tx_valid      (debug_tx_valid),
        .debug_tx_ready      (debug_tx_ready),
        .debug_busy          (debug_busy),
        .debug_done_pulse    (debug_done_pulse),

        .debug_pending       (debug_pending),
        .debug_start         (debug_start),

        .uart_tx_data        (uart_tx_data),
        .uart_tx_valid       (uart_tx_valid),
        .uart_tx_ready       (uart_tx_ready)
    );

    // ============================================================
    // Sequencer
    // ============================================================

    instr_sequencer u_instr_sequencer (
        .clk                   (clk),
        .rst_sync_n            (rst_sync_n),

        .init_done             (init_done),
        .reset_wait_cycles     (reset_wait_cycles),

        .rd_instr_addr         (rd_instr_addr),
        .rd_instr_data         (rd_instr_data),

        .rd_play_cfg_addr      (rd_play_cfg_addr),
        .rd_play_cfg_data      (rd_play_cfg_data),

        .rd_measure_cfg_addr   (rd_measure_cfg_addr),
        .rd_measure_cfg_data   (rd_measure_cfg_data),

        .formatter_start       (formatter_start),
        .formatter_is_play     (formatter_is_play),
        .formatter_is_reset    (formatter_is_reset),
        .formatter_cfg_index   (formatter_cfg_index),
        .formatter_play_cfg    (formatter_play_cfg),
        .formatter_measure_cfg (formatter_measure_cfg),
        .formatter_busy        (formatter_busy),
        .formatter_done_pulse  (formatter_done_pulse),

        .measure_start         (measure_start),
        .measure_rsp_done_pulse(measure_rsp_done_pulse),

        .cal_accum_clear       (cal_accum_clear),
        .cal_accum_push        (cal_accum_push),
        .cal_accum_finalize    (cal_accum_finalize),
        .cal_accum_store_sel   (cal_accum_store_sel),
        .cal_accum_done_pulse  (cal_accum_done_pulse),

        .seq_busy              (seq_busy),
        .seq_done_pulse        (seq_done_pulse_in)
    );

    // ============================================================
    // Calibration accumulator
    // ============================================================

    calibration_accumulator u_calibration_accumulator (
        .clk          (clk),
        .rst_sync_n   (rst_sync_n),

        .clear        (cal_accum_clear),
        .push         (cal_accum_push),
        .finalize     (cal_accum_finalize),

        .i_in         (measure_i_avg),
        .q_in         (measure_q_avg),

        .busy         (cal_accum_busy),
        .done_pulse   (cal_accum_done_pulse),
        .avg_valid    (cal_accum_avg_valid),
        .sample_count (cal_accum_sample_count),
        .i_avg        (cal_accum_i_avg),
        .q_avg        (cal_accum_q_avg)
    );

    // ============================================================
    // Command formatter
    // ============================================================

    cmd_formatter u_cmd_formatter (
        .clk         (clk),
        .rst_sync_n  (rst_sync_n),

        .start       (formatter_start),
        .is_play     (formatter_is_play),
        .is_reset    (formatter_is_reset),
        .cfg_index   (formatter_cfg_index),
        .play_cfg    (formatter_play_cfg),
        .measure_cfg (formatter_measure_cfg),

        .tx_data     (formatter_tx_data),
        .tx_valid    (formatter_tx_valid),
        .tx_ready    (formatter_tx_ready),

        .busy        (formatter_busy),
        .done_pulse  (formatter_done_pulse)
    );

    // ============================================================
    // Measure response receiver
    // ============================================================

    measure_response_rx u_measure_response_rx (
        .clk           (clk),
        .rst_sync_n    (rst_sync_n),

        .rx_byte_valid (uart_dout_vld),
        .rx_byte       (uart_dout),

        .busy          (measure_rsp_busy),
        .done_pulse    (measure_rsp_done_pulse),

        .resp_valid    (measure_rsp_valid),
        .sample_count  (measure_rsp_sample_count),
        .i_avg         (measure_i_avg),
        .q_avg         (measure_q_avg)
    );

    // ============================================================
    // Debug formatter
    // ============================================================

    debug u_debug (
        .clk                (clk),
        .rst_sync_n         (rst_sync_n),

        .start              (debug_start),
        .cal_update         (debug_pending_is_cal),
        .i_avg              (debug_i_avg_sel),
        .q_avg              (debug_q_avg_sel),
        .cal_i_threshold    (reg_cal_i_threshold),
        .cal_state_polarity (reg_cal_state_polarity),
        .meas_state         (reg_meas_state),
        .meas_state_valid   (reg_meas_state_valid),

        .tx_data            (debug_tx_data),
        .tx_valid           (debug_tx_valid),
        .tx_ready           (debug_tx_ready),

        .busy               (debug_busy),
        .done_pulse         (debug_done_pulse)
    );

endmodule
