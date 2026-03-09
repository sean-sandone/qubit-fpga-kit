// uart_play_sender_top.sv


module uart_play_sender_top #(  //KCU105
    parameter int CLK_FREQ_HZ = 125_000_000,
    parameter int BAUD_RATE   = 115200,
    parameter int unsigned STEP_HZ = 5 // used for led blink timing
)(
    input  logic USB_UART_TX,   // labeled from the perspective of the USB UART transceiver chip
    output logic USB_UART_RX,   // unused here, but connected to UART entity

    input  logic clk_125mhz_p,
    input  logic clk_125mhz_n,
    input  logic CPU_RESET,      // active high async reset (input)
    output logic GPIO_LED_0_LS,
    output logic GPIO_LED_1_LS,
    output logic GPIO_LED_2_LS,
    output logic GPIO_LED_3_LS,
    output logic GPIO_LED_4_LS,
    output logic GPIO_LED_5_LS,
    output logic GPIO_LED_6_LS,
    output logic GPIO_LED_7_LS
);

    // Clocking
    logic clk;

    // Reset sync (active low internal reset)
    logic rst_ff1_n, rst_ff2_n;
    logic rst_sync_n, rst_sync;

    // UART Signals
    logic uart_txd, uart_rxd;

    // Differential clock input buffer (Xilinx)
    IBUFDS ibufds_sysclk (
        .I (clk_125mhz_p),
        .IB(clk_125mhz_n),
        .O (clk)
    );

    // Reset synchronizer: async assert, sync deassert
    always_ff @(posedge clk or posedge CPU_RESET) begin
        if (CPU_RESET) begin
        rst_ff1_n <= 1'b0;
        rst_ff2_n <= 1'b0;
        end else begin
        rst_ff1_n <= 1'b1;
        rst_ff2_n <= rst_ff1_n;
        end
    end

    assign rst_sync_n = rst_ff2_n;   // active low internal reset
    assign rst_sync = !rst_ff2_n; // active HIGH internal reset

    // Swap UART signals
    assign uart_rxd = USB_UART_TX;
    assign USB_UART_RX = uart_txd;

    // ----------------------------
    // VHDL UART signals
    // ----------------------------
    logic [7:0] din;
    logic       din_vld;
    logic       din_rdy;

    logic [7:0] dout;
    logic       dout_vld;
    logic       frame_error;
    logic       parity_error;

    // Instantiate the VHDL UART (mixed-language in Vivado)
    UART #(
        .CLK_FREQ      (CLK_FREQ_HZ),
        .BAUD_RATE     (BAUD_RATE),
        .PARITY_BIT    ("none"),
        .USE_DEBOUNCER (1)
    ) u_uart (
        .CLK          (clk),
        .RST          (rst_sync),
        .UART_TXD     (uart_txd), // Transmit to the host
        .UART_RXD     (uart_rxd), // Recieve from the host
        .DIN          (din),
        .DIN_VLD      (din_vld),
        .DIN_RDY      (din_rdy),
        .DOUT         (dout),
        .DOUT_VLD     (dout_vld),
        .FRAME_ERROR  (frame_error),
        .PARITY_ERROR (parity_error)
    );

    // ----------------------------
    // Message ROM (ASCII JSON + '\n')
    // For quick bring-up this uses a synthesizable ROM init style
    // using a case statement.
    // ----------------------------
    localparam int MsgLen = 102; // 0..101 inclusive
    //localparam int MsgLen = 2;

    function automatic logic [7:0] msg_byte(input int idx);
        case (idx)
            // {"cmd":"PLAY","amp":1.0,"phase":0.0,"duration_s":2e-7,"envelope":"gauss","sigma_s":3e-8,"pad_s":2e-7}\n
            //0:  msg_byte = 8'h55; // U
            //1:  msg_byte = 8'h0A; // \n
            0:  msg_byte = 8'h7B; // {
            1:  msg_byte = 8'h22; // "
            2:  msg_byte = 8'h63; // c
            3:  msg_byte = 8'h6D; // m
            4:  msg_byte = 8'h64; // d
            5:  msg_byte = 8'h22; // "
            6:  msg_byte = 8'h3A; // :
            7:  msg_byte = 8'h22; // "
            8:  msg_byte = 8'h50; // P
            9:  msg_byte = 8'h4C; // L
            10: msg_byte = 8'h41; // A
            11: msg_byte = 8'h59; // Y
            12: msg_byte = 8'h22; // "
            13: msg_byte = 8'h2C; // ,
            14: msg_byte = 8'h22; // "
            15: msg_byte = 8'h61; // a
            16: msg_byte = 8'h6D; // m
            17: msg_byte = 8'h70; // p
            18: msg_byte = 8'h22; // "
            19: msg_byte = 8'h3A; // :
            20: msg_byte = 8'h31; // 1
            21: msg_byte = 8'h2E; // .
            22: msg_byte = 8'h30; // 0
            23: msg_byte = 8'h2C; // ,
            24: msg_byte = 8'h22; // "
            25: msg_byte = 8'h70; // p
            26: msg_byte = 8'h68; // h
            27: msg_byte = 8'h61; // a
            28: msg_byte = 8'h73; // s
            29: msg_byte = 8'h65; // e
            30: msg_byte = 8'h22; // "
            31: msg_byte = 8'h3A; // :
            32: msg_byte = 8'h30; // 0
            33: msg_byte = 8'h2E; // .
            34: msg_byte = 8'h30; // 0
            35: msg_byte = 8'h2C; // ,
            36: msg_byte = 8'h22; // "
            37: msg_byte = 8'h64; // d
            38: msg_byte = 8'h75; // u
            39: msg_byte = 8'h72; // r
            40: msg_byte = 8'h61; // a
            41: msg_byte = 8'h74; // t
            42: msg_byte = 8'h69; // i
            43: msg_byte = 8'h6F; // o
            44: msg_byte = 8'h6E; // n
            45: msg_byte = 8'h5F; // _
            46: msg_byte = 8'h73; // s
            47: msg_byte = 8'h22; // "
            48: msg_byte = 8'h3A; // :
            49: msg_byte = 8'h32; // 2
            50: msg_byte = 8'h65; // e
            51: msg_byte = 8'h2D; // -
            52: msg_byte = 8'h37; // 7
            53: msg_byte = 8'h2C; // ,
            54: msg_byte = 8'h22; // "
            55: msg_byte = 8'h65; // e
            56: msg_byte = 8'h6E; // n
            57: msg_byte = 8'h76; // v
            58: msg_byte = 8'h65; // e
            59: msg_byte = 8'h6C; // l
            60: msg_byte = 8'h6F; // o
            61: msg_byte = 8'h70; // p
            62: msg_byte = 8'h65; // e
            63: msg_byte = 8'h22; // "
            64: msg_byte = 8'h3A; // :
            65: msg_byte = 8'h22; // "
            66: msg_byte = 8'h67; // g
            67: msg_byte = 8'h61; // a
            68: msg_byte = 8'h75; // u
            69: msg_byte = 8'h73; // s
            70: msg_byte = 8'h73; // s
            71: msg_byte = 8'h22; // "
            72: msg_byte = 8'h2C; // ,
            73: msg_byte = 8'h22; // "
            74: msg_byte = 8'h73; // s
            75: msg_byte = 8'h69; // i
            76: msg_byte = 8'h67; // g
            77: msg_byte = 8'h6D; // m
            78: msg_byte = 8'h61; // a
            79: msg_byte = 8'h5F; // _
            80: msg_byte = 8'h73; // s
            81: msg_byte = 8'h22; // "
            82: msg_byte = 8'h3A; // :
            83: msg_byte = 8'h33; // 3
            84: msg_byte = 8'h65; // e
            85: msg_byte = 8'h2D; // -
            86: msg_byte = 8'h38; // 8
            87: msg_byte = 8'h2C; // ,
            88: msg_byte = 8'h22; // "
            89: msg_byte = 8'h70; // p
            90: msg_byte = 8'h61; // a
            91: msg_byte = 8'h64; // d
            92: msg_byte = 8'h5F; // _
            93: msg_byte = 8'h73; // s
            94: msg_byte = 8'h22; // "
            95: msg_byte = 8'h3A; // :
            96: msg_byte = 8'h32; // 2
            97: msg_byte = 8'h65; // e
            98: msg_byte = 8'h2D; // -
            99: msg_byte = 8'h37; // 7
            100: msg_byte = 8'h7D; // }
            101: msg_byte = 8'h0A; // \n
            default: msg_byte = 8'h20; // space padding
        endcase
    endfunction

    // ----------------------------
    // Sender FSM: pushes bytes when DIN_RDY is high
    // ----------------------------
    typedef enum logic [1:0] {
        S_IDLE,
        S_PRESENT,
        S_ADVANCE,
        S_DONE
    } state_t;

    state_t st;
    int unsigned idx;

    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
            st      <= S_IDLE;
            idx     <= 0;
            din     <= 8'h00;
            din_vld <= 1'b0;
        end else begin
            case (st)
                S_IDLE: begin
                    idx     <= 0;
                    din     <= msg_byte(0);
                    din_vld <= 1'b1;
                    st      <= S_PRESENT;
                end

                S_PRESENT: begin
                    // Hold current byte stable until handshake occurs
                    din     <= din;
                    din_vld <= 1'b1;

                    if (din_rdy) begin
                        st <= S_ADVANCE;
                    end
                end

                S_ADVANCE: begin
                    if (idx == MsgLen-1) begin
                        din_vld <= 1'b0;
                        st      <= S_DONE;
                    end else begin
                        idx     <= idx + 1;
                        din     <= msg_byte(idx + 1);
                        din_vld <= 1'b1;
                        st      <= S_PRESENT;
                    end
                end

                S_DONE: begin
                    din_vld <= 1'b0;
                end

                default: begin
                    st      <= S_IDLE;
                    idx     <= 0;
                    din     <= 8'h00;
                    din_vld <= 1'b0;
                end
            endcase
        end
end


    // Derived constants
    `ifdef SIM
        localparam int unsigned TickDiv = 100;   // 100 cycles per "second" in sim
    `else
        localparam int unsigned TickDiv = (CLK_FREQ_HZ / STEP_HZ); // real world div
    `endif


    // Tick divider and LED state
    logic [$clog2(TickDiv)-1:0] tick_cnt;
    logic tick;

    logic shifting_left;     // 1 = shift left toward bit 7, 0 = shift right toward bit 0
    logic [5:0] led_c;


    // Generate 1-cycle tick
    assign tick = (tick_cnt == TickDiv-1);

    // Main state machine: tick divider + shift register bounce
    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
        tick_cnt       <= '0;
        shifting_left  <= 1'b1;
        led_c          <= 6'b00_0001;
        end else begin
        if (tick) begin
            tick_cnt <= '0;

            if (shifting_left) begin
            if (led_c[5]) begin
                shifting_left <= 1'b0;               // bounce: next go right
                led_c         <= {1'b0, led_c[5:1]}; // 5 -> 4
            end else begin
                led_c <= {led_c[4:0], 1'b0};
            end
            end else begin
            if (led_c[0]) begin
                shifting_left <= 1'b1;               // bounce: next go left
                led_c         <= {led_c[4:0], 1'b0}; // 0 -> 1
            end else begin
                led_c <= {1'b0, led_c[5:1]};
            end
            end

        end else begin
            tick_cnt <= tick_cnt + 1'b1;
        end
        end
    end

    // Drive individual outputs from vector
    assign GPIO_LED_0_LS = led_c[0];
    assign GPIO_LED_1_LS = led_c[1];
    assign GPIO_LED_2_LS = led_c[2];
    assign GPIO_LED_3_LS = led_c[3];
    assign GPIO_LED_4_LS = led_c[4];
    assign GPIO_LED_5_LS = led_c[5];
    // Drive last two leds from tx/rx
    assign GPIO_LED_6_LS = uart_txd;
    assign GPIO_LED_7_LS = uart_rxd;

endmodule
