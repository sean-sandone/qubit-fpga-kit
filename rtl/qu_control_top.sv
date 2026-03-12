module qu_control_top #(  // Xilinx KCU105 Eval Board
    parameter int CLK_FREQ_HZ = 125_000_000,
    parameter int BAUD_RATE   = 115200,
    parameter int unsigned STEP_HZ = 5  // used for led blink timing
)(
    input  logic USB_UART_TX,  // labeled from the perspective of the USB UART transceiver chip
    output logic USB_UART_RX,  // labeled from the perspective of the USB UART transceiver chip

    input  logic clk_125mhz_p,
    input  logic clk_125mhz_n,
    input  logic CPU_RESET,    // active high async reset (input)

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

    IBUFDS ibufds_sysclk (
        .I (clk_125mhz_p),
        .IB(clk_125mhz_n),
        .O (clk)
    );

    // ============================================================
    // Reset synchronizer
    // async assert, sync deassert
    // ============================================================

    logic rst_ff1_n;
    logic rst_ff2_n;
    logic rst_sync_n;
    logic rst_sync;

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

    uart_frontend #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE)
    ) u_uart_frontend (
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

    logic start_exp;
    logic soft_reset_req;

    logic play_cfg_any_valid;
    logic measure_cfg_any_valid;
    logic instr_any_valid;

    logic seq_busy;
    logic seq_done_sticky;

    logic seq_done_pulse_in;
    logic clear_start_exp;

    assign clear_start_exp = 1'b0;

    // ============================================================
    // Register bank
    // ============================================================

    register_bank u_register_bank (
        .clk                   (clk),
        .rst_sync_n            (rst_sync_n),

        .wr_control            (init_wr_control),
        .control_start_exp_in  (init_control_start_exp),
        .control_soft_reset_in (init_control_soft_reset),

        .wr_play_cfg           (init_wr_play_cfg),
        .wr_play_cfg_addr      (init_wr_play_cfg_addr),
        .wr_play_cfg_data      (init_wr_play_cfg_data),

        .wr_measure_cfg        (init_wr_measure_cfg),
        .wr_measure_cfg_addr   (init_wr_measure_cfg_addr),
        .wr_measure_cfg_data   (init_wr_measure_cfg_data),

        .wr_instr              (init_wr_instr),
        .wr_instr_addr         (init_wr_instr_addr),
        .wr_instr_data         (init_wr_instr_data),

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

        .play_cfg_any_valid    (play_cfg_any_valid),
        .measure_cfg_any_valid (measure_cfg_any_valid),
        .instr_any_valid       (instr_any_valid),

        .seq_busy              (seq_busy),
        .seq_done_sticky       (seq_done_sticky)
    );

    // ============================================================
    // Sequencer -> formatter path
    // ============================================================

    logic                 formatter_start;
    logic                 formatter_is_play;
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

    logic        measure_rsp_busy;
    logic        measure_rsp_done_pulse;
    logic        measure_rsp_valid;
    logic [7:0]  measure_rsp_sample_count;
    logic signed [15:0] measure_i_avg;
    logic signed [15:0] measure_q_avg;

    // ============================================================
    // Debug UART source
    // ============================================================

    logic        debug_start;
    logic [7:0]  debug_tx_data;
    logic        debug_tx_valid;
    logic        debug_tx_ready;
    logic        debug_busy;
    logic        debug_done_pulse;

    assign debug_start = measure_rsp_done_pulse;

    // ============================================================
    // UART TX arbitration
    // Debug has priority over formatter if both ever assert together
    // ============================================================

    always_comb begin
        uart_tx_data        = formatter_tx_data;
        uart_tx_valid       = formatter_tx_valid;
        formatter_tx_ready  = uart_tx_ready;
        debug_tx_ready      = 1'b0;

        if (debug_busy || debug_tx_valid) begin
            uart_tx_data       = debug_tx_data;
            uart_tx_valid      = debug_tx_valid;
            debug_tx_ready     = uart_tx_ready;
            formatter_tx_ready = 1'b0;
        end
    end

    instr_sequencer u_instr_sequencer (
        .clk                  (clk),
        .rst_sync_n           (rst_sync_n),

        .init_done            (init_done),

        .rd_instr_addr        (rd_instr_addr),
        .rd_instr_data        (rd_instr_data),

        .rd_play_cfg_addr     (rd_play_cfg_addr),
        .rd_play_cfg_data     (rd_play_cfg_data),

        .rd_measure_cfg_addr  (rd_measure_cfg_addr),
        .rd_measure_cfg_data  (rd_measure_cfg_data),

        .formatter_start      (formatter_start),
        .formatter_is_play    (formatter_is_play),
        .formatter_cfg_index  (formatter_cfg_index),
        .formatter_play_cfg   (formatter_play_cfg),
        .formatter_measure_cfg(formatter_measure_cfg),
        .formatter_busy       (formatter_busy),
        .formatter_done_pulse (formatter_done_pulse),

        .measure_rsp_done_pulse(measure_rsp_done_pulse),

        .seq_busy             (seq_busy),
        .seq_done_pulse       (seq_done_pulse_in)
    );

    cmd_formatter u_cmd_formatter (
        .clk         (clk),
        .rst_sync_n  (rst_sync_n),

        .start       (formatter_start),
        .is_play     (formatter_is_play),
        .cfg_index   (formatter_cfg_index),
        .play_cfg    (formatter_play_cfg),
        .measure_cfg (formatter_measure_cfg),

        .tx_data     (formatter_tx_data),
        .tx_valid    (formatter_tx_valid),
        .tx_ready    (formatter_tx_ready),

        .busy        (formatter_busy),
        .done_pulse  (formatter_done_pulse)
    );

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

    debug u_debug (
        .clk        (clk),
        .rst_sync_n (rst_sync_n),

        .start      (debug_start),
        .i_avg      (measure_i_avg),
        .q_avg      (measure_q_avg),

        .tx_data    (debug_tx_data),
        .tx_valid   (debug_tx_valid),
        .tx_ready   (debug_tx_ready),

        .busy       (debug_busy),
        .done_pulse (debug_done_pulse)
    );

endmodule
