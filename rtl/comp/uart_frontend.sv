module uart_frontend #(
    parameter int CLK_FREQ_HZ = 125_000_000,
    parameter int BAUD_RATE   = 115200
)(
    input  logic clk,
    input  logic rst_sync,     // active high
    input  logic rst_sync_n,   // active low

    input  logic usb_uart_tx_in,
    output logic usb_uart_rx_out,

    output logic uart_txd_mon,
    output logic uart_rxd_mon,

    output logic dout_vld,
    output logic frame_error,
    output logic parity_error,
    output logic [7:0] dout
);

    import rtl_pkg::*;

    // Physical UART wires at FPGA boundary
    logic uart_txd;
    logic uart_rxd;

    // UART core handshake
    logic [7:0] din;
    logic       din_vld;
    logic       din_rdy;

    // Sender state
    uart_tx_state_t st;
    int unsigned idx;

    // Swap UART signals to match board labeling
    assign uart_rxd       = usb_uart_tx_in;
    assign usb_uart_rx_out = uart_txd;

    // Monitor outputs for LEDs / debug
    assign uart_txd_mon = uart_txd;
    assign uart_rxd_mon = uart_rxd;

    // ----------------------------
    // VHDL UART instance
    // ----------------------------
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
        .DIN          (din),
        .DIN_VLD      (din_vld),
        .DIN_RDY      (din_rdy),
        .DOUT         (dout),
        .DOUT_VLD     (dout_vld),
        .FRAME_ERROR  (frame_error),
        .PARITY_ERROR (parity_error)
    );

    // ----------------------------
    // Message ROM
    // Current demo behavior:
    // sends one JSON PLAY command followed by newline.
    // ----------------------------
    function automatic logic [7:0] msg_byte(input int msg_idx);
        case (msg_idx)
            0:   msg_byte = 8'h7B; // {
            1:   msg_byte = 8'h22; // "
            2:   msg_byte = 8'h63; // c
            3:   msg_byte = 8'h6D; // m
            4:   msg_byte = 8'h64; // d
            5:   msg_byte = 8'h22; // "
            6:   msg_byte = 8'h3A; // :
            7:   msg_byte = 8'h22; // "
            8:   msg_byte = 8'h50; // P
            9:   msg_byte = 8'h4C; // L
            10:  msg_byte = 8'h41; // A
            11:  msg_byte = 8'h59; // Y
            12:  msg_byte = 8'h22; // "
            13:  msg_byte = 8'h2C; // ,
            14:  msg_byte = 8'h22; // "
            15:  msg_byte = 8'h61; // a
            16:  msg_byte = 8'h6D; // m
            17:  msg_byte = 8'h70; // p
            18:  msg_byte = 8'h22; // "
            19:  msg_byte = 8'h3A; // :
            20:  msg_byte = 8'h31; // 1
            21:  msg_byte = 8'h2E; // .
            22:  msg_byte = 8'h30; // 0
            23:  msg_byte = 8'h2C; // ,
            24:  msg_byte = 8'h22; // "
            25:  msg_byte = 8'h70; // p
            26:  msg_byte = 8'h68; // h
            27:  msg_byte = 8'h61; // a
            28:  msg_byte = 8'h73; // s
            29:  msg_byte = 8'h65; // e
            30:  msg_byte = 8'h22; // "
            31:  msg_byte = 8'h3A; // :
            32:  msg_byte = 8'h30; // 0
            33:  msg_byte = 8'h2E; // .
            34:  msg_byte = 8'h30; // 0
            35:  msg_byte = 8'h2C; // ,
            36:  msg_byte = 8'h22; // "
            37:  msg_byte = 8'h64; // d
            38:  msg_byte = 8'h75; // u
            39:  msg_byte = 8'h72; // r
            40:  msg_byte = 8'h61; // a
            41:  msg_byte = 8'h74; // t
            42:  msg_byte = 8'h69; // i
            43:  msg_byte = 8'h6F; // o
            44:  msg_byte = 8'h6E; // n
            45:  msg_byte = 8'h5F; // _
            46:  msg_byte = 8'h73; // s
            47:  msg_byte = 8'h22; // "
            48:  msg_byte = 8'h3A; // :
            49:  msg_byte = 8'h32; // 2
            50:  msg_byte = 8'h65; // e
            51:  msg_byte = 8'h2D; // -
            52:  msg_byte = 8'h37; // 7
            53:  msg_byte = 8'h2C; // ,
            54:  msg_byte = 8'h22; // "
            55:  msg_byte = 8'h65; // e
            56:  msg_byte = 8'h6E; // n
            57:  msg_byte = 8'h76; // v
            58:  msg_byte = 8'h65; // e
            59:  msg_byte = 8'h6C; // l
            60:  msg_byte = 8'h6F; // o
            61:  msg_byte = 8'h70; // p
            62:  msg_byte = 8'h65; // e
            63:  msg_byte = 8'h22; // "
            64:  msg_byte = 8'h3A; // :
            65:  msg_byte = 8'h22; // "
            66:  msg_byte = 8'h67; // g
            67:  msg_byte = 8'h61; // a
            68:  msg_byte = 8'h75; // u
            69:  msg_byte = 8'h73; // s
            70:  msg_byte = 8'h73; // s
            71:  msg_byte = 8'h22; // "
            72:  msg_byte = 8'h2C; // ,
            73:  msg_byte = 8'h22; // "
            74:  msg_byte = 8'h73; // s
            75:  msg_byte = 8'h69; // i
            76:  msg_byte = 8'h67; // g
            77:  msg_byte = 8'h6D; // m
            78:  msg_byte = 8'h61; // a
            79:  msg_byte = 8'h5F; // _
            80:  msg_byte = 8'h73; // s
            81:  msg_byte = 8'h22; // "
            82:  msg_byte = 8'h3A; // :
            83:  msg_byte = 8'h33; // 3
            84:  msg_byte = 8'h65; // e
            85:  msg_byte = 8'h2D; // -
            86:  msg_byte = 8'h38; // 8
            87:  msg_byte = 8'h2C; // ,
            88:  msg_byte = 8'h22; // "
            89:  msg_byte = 8'h70; // p
            90:  msg_byte = 8'h61; // a
            91:  msg_byte = 8'h64; // d
            92:  msg_byte = 8'h5F; // _
            93:  msg_byte = 8'h73; // s
            94:  msg_byte = 8'h22; // "
            95:  msg_byte = 8'h3A; // :
            96:  msg_byte = 8'h32; // 2
            97:  msg_byte = 8'h65; // e
            98:  msg_byte = 8'h2D; // -
            99:  msg_byte = 8'h37; // 7
            100: msg_byte = 8'h7D; // }
            101: msg_byte = 8'h0A; // \n
            default: msg_byte = 8'h20;
        endcase
    endfunction

    // ----------------------------
    // Current one-shot sender FSM
    // ----------------------------
    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
            st      <= UART_TX_IDLE;
            idx     <= 0;
            din     <= 8'h00;
            din_vld <= 1'b0;
        end else begin
            case (st)
                UART_TX_IDLE: begin
                    idx     <= 0;
                    din     <= msg_byte(0);
                    din_vld <= 1'b1;
                    st      <= UART_TX_PRESENT;
                end

                UART_TX_PRESENT: begin
                    din     <= din;
                    din_vld <= 1'b1;

                    if (din_rdy) begin
                        st <= UART_TX_ADVANCE;
                    end
                end

                UART_TX_ADVANCE: begin
                    if (idx == MsgLen - 1) begin
                        din_vld <= 1'b0;
                        st      <= UART_TX_DONE;
                    end else begin
                        idx     <= idx + 1;
                        din     <= msg_byte(idx + 1);
                        din_vld <= 1'b1;
                        st      <= UART_TX_PRESENT;
                    end
                end

                UART_TX_DONE: begin
                    din_vld <= 1'b0;
                end

                default: begin
                    st      <= UART_TX_IDLE;
                    idx     <= 0;
                    din     <= 8'h00;
                    din_vld <= 1'b0;
                end
            endcase
        end
    end

endmodule
