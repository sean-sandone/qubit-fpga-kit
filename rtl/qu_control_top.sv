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
    logic reg_cal_debug_update_pulse;
    logic cal_debug_ref0_sel_r;

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

        .wr_cal_results        (cal_accum_done_pulse),
        .cal_store_sel_in      (cal_accum_store_sel),
        .cal_sample_count_in   (cal_accum_sample_count),
        .cal_i_avg_in          (cal_accum_i_avg),
        .cal_q_avg_in          (cal_accum_q_avg),

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

        .cal_debug_update_pulse(reg_cal_debug_update_pulse)
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
    logic               debug_cal_update;
    logic [7:0]         debug_tx_data;
    logic               debug_tx_valid;
    logic               debug_tx_ready;
    logic               debug_busy;
    logic               debug_done_pulse;
    logic               debug_pending_r;
    logic               debug_pending_is_cal_r;
    logic signed [15:0] debug_i_avg_sel;
    logic signed [15:0] debug_q_avg_sel;

    // ============================================================
    // Message-atomic UART TX arbitration
    // One source owns the UART until its full message is complete
    // ============================================================

    typedef enum logic [1:0] {
        TxOwnerNone      = 2'd0,
        TxOwnerFormatter = 2'd1,
        TxOwnerDebug     = 2'd2
    } tx_owner_t;

    tx_owner_t tx_owner_r;

    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
            tx_owner_r <= TxOwnerNone;
        end else begin
            case (tx_owner_r)
                TxOwnerNone: begin
                    if (formatter_busy) begin
                        tx_owner_r <= TxOwnerFormatter;
                    end else if (debug_busy) begin
                        tx_owner_r <= TxOwnerDebug;
                    end
                end

                TxOwnerFormatter: begin
                    if (formatter_done_pulse) begin
                        tx_owner_r <= TxOwnerNone;
                    end
                end

                TxOwnerDebug: begin
                    if (debug_done_pulse) begin
                        tx_owner_r <= TxOwnerNone;
                    end
                end

                default: begin
                    tx_owner_r <= TxOwnerNone;
                end
            endcase
        end
    end

    // ============================================================
    // Latch debug requests until UART ownership is available
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
            debug_pending_r        <= 1'b0;
            debug_pending_is_cal_r <= 1'b0;
        end else begin
            if (reg_cal_debug_update_pulse) begin
                debug_pending_r        <= 1'b1;
                debug_pending_is_cal_r <= 1'b1;
            end else if (measure_rsp_done_pulse) begin
                debug_pending_r        <= 1'b1;
                debug_pending_is_cal_r <= 1'b0;
            end else if (debug_start) begin
                debug_pending_r        <= 1'b0;
                debug_pending_is_cal_r <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
            cal_debug_ref0_sel_r <= 1'b0;
        end else begin
            if (cal_accum_done_pulse) begin
                case (cal_accum_store_sel)
                    CAL_DEST_REF0: cal_debug_ref0_sel_r <= 1'b1;
                    CAL_DEST_REF1: cal_debug_ref0_sel_r <= 1'b0;
                    default: begin
                    end
                endcase
            end
        end
    end

    assign debug_start      = debug_pending_r && (tx_owner_r == TxOwnerNone);
    assign debug_cal_update = debug_pending_is_cal_r;

    always_comb begin
        if (debug_cal_update) begin
            if (cal_debug_ref0_sel_r) begin
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

    // ============================================================
    // UART TX routing by locked owner
    // ============================================================

    always_comb begin
        uart_tx_data       = 8'h00;
        uart_tx_valid      = 1'b0;
        formatter_tx_ready = 1'b0;
        debug_tx_ready     = 1'b0;

        case (tx_owner_r)
            TxOwnerFormatter: begin
                uart_tx_data       = formatter_tx_data;
                uart_tx_valid      = formatter_tx_valid;
                formatter_tx_ready = uart_tx_ready;
            end

            TxOwnerDebug: begin
                uart_tx_data   = debug_tx_data;
                uart_tx_valid  = debug_tx_valid;
                debug_tx_ready = uart_tx_ready;
            end

            default: begin
            end
        endcase
    end

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
        .cal_update         (debug_cal_update),
        .i_avg              (debug_i_avg_sel),
        .q_avg              (debug_q_avg_sel),
        .cal_i_threshold    (reg_cal_i_threshold),
        .cal_state_polarity (reg_cal_state_polarity),

        .tx_data            (debug_tx_data),
        .tx_valid           (debug_tx_valid),
        .tx_ready           (debug_tx_ready),

        .busy               (debug_busy),
        .done_pulse         (debug_done_pulse)
    );

endmodule
