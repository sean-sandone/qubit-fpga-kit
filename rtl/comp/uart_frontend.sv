module uart_frontend #(
    parameter int CLK_FREQ_HZ = 125_000_000,
    parameter int BAUD_RATE   = 115200
)(
    input  logic clk,
    input  logic rst_sync,     // active high
    input  logic rst_sync_n,   // active low

    input  logic usb_uart_tx_in,   // labeled from the perspective of the USB UART transceiver chip
    output logic usb_uart_rx_out,  // labeled from the perspective of the USB UART transceiver chip

    output logic uart_txd_mon,
    output logic uart_rxd_mon,

    input  logic [7:0] tx_data,
    input  logic       tx_valid,
    output logic       tx_ready,

    output logic dout_vld,
    output logic frame_error,
    output logic parity_error,
    output logic [7:0] dout
);

    logic uart_txd;
    logic uart_rxd;

    assign uart_rxd        = usb_uart_tx_in;
    assign usb_uart_rx_out = uart_txd;

    assign uart_txd_mon = uart_txd;
    assign uart_rxd_mon = uart_rxd;

    UART #(
        .CLK_FREQ      (CLK_FREQ_HZ),
        .BAUD_RATE     (BAUD_RATE),
        .PARITY_BIT    ("none"),
        .USE_DEBOUNCER (1)
    ) u_uart (
        .CLK          (clk),
        .RST          (rst_sync),
        .UART_TXD     (uart_txd),
        .UART_RXD     (uart_rxd),
        .DIN          (tx_data),
        .DIN_VLD      (tx_valid),
        .DIN_RDY      (tx_ready),
        .DOUT         (dout),
        .DOUT_VLD     (dout_vld),
        .FRAME_ERROR  (frame_error),
        .PARITY_ERROR (parity_error)
    );

endmodule
