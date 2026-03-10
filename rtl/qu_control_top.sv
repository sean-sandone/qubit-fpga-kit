module qu_control_top #(  // Xilinx KCU105 Eval Board
    parameter int CLK_FREQ_HZ = 125_000_000,
    parameter int BAUD_RATE   = 115200,
    parameter int unsigned STEP_HZ = 5 // used for led blink timing
)(
    input  logic USB_UART_TX,  // labeled from the perspective of the USB UART transceiver chip
    output logic USB_UART_RX,

    input  logic clk_125mhz_p,
    input  logic clk_125mhz_n,
    input  logic CPU_RESET,     // active high async reset (input)

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

    // ----------------------------
    // Clocking
    // ----------------------------
    logic clk;

    IBUFDS ibufds_sysclk (
        .I (clk_125mhz_p),
        .IB(clk_125mhz_n),
        .O (clk)
    );

    // ----------------------------
    // Reset synchronizer
    // async assert, sync deassert
    // ----------------------------
    logic rst_ff1_n, rst_ff2_n;
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

    // ----------------------------
    // UART monitor signals
    // ----------------------------
    logic uart_txd_mon;
    logic uart_rxd_mon;

    // UART RX outputs for future use / debug
    logic [7:0] uart_dout;
    logic       uart_dout_vld;
    logic       frame_error;
    logic       parity_error;

    // ----------------------------
    // UART frontend
    // ----------------------------
    uart_frontend #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE)
    ) u_uart_frontend (
        .clk            (clk),
        .rst_sync       (rst_sync),
        .rst_sync_n     (rst_sync_n),

        .usb_uart_tx_in (USB_UART_TX),
        .usb_uart_rx_out(USB_UART_RX),

        .uart_txd_mon   (uart_txd_mon),
        .uart_rxd_mon   (uart_rxd_mon),

        .dout_vld       (uart_dout_vld),
        .frame_error    (frame_error),
        .parity_error   (parity_error),
        .dout           (uart_dout)
    );

    // ----------------------------
    // LED engine
    // ----------------------------
    leds #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .STEP_HZ    (STEP_HZ)
    ) u_leds (
        .clk          (clk),
        .rst_sync_n   (rst_sync_n),

        .uart_txd_mon (uart_txd_mon),
        .uart_rxd_mon (uart_rxd_mon),

        .GPIO_LED_0_LS(GPIO_LED_0_LS),
        .GPIO_LED_1_LS(GPIO_LED_1_LS),
        .GPIO_LED_2_LS(GPIO_LED_2_LS),
        .GPIO_LED_3_LS(GPIO_LED_3_LS),
        .GPIO_LED_4_LS(GPIO_LED_4_LS),
        .GPIO_LED_5_LS(GPIO_LED_5_LS),
        .GPIO_LED_6_LS(GPIO_LED_6_LS),
        .GPIO_LED_7_LS(GPIO_LED_7_LS)
    );

endmodule
