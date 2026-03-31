`timescale 1ns/1ps

module qu_control_top_tb;

    localparam int CLK_FREQ_HZ = 20_000_000;
    localparam int BAUD_RATE   = 115200;
    localparam time CLK_PERIOD = 50ns;
    localparam time BIT_PERIOD = 1_000_000_000ns / BAUD_RATE;

    logic clk_125mhz_p;
    logic clk_125mhz_n;

    logic USB_UART_TX;
    logic USB_UART_RX;

    logic CPU_RESET;

    logic GPIO_LED_0_LS;
    logic GPIO_LED_1_LS;
    logic GPIO_LED_2_LS;
    logic GPIO_LED_3_LS;
    logic GPIO_LED_4_LS;
    logic GPIO_LED_5_LS;
    logic GPIO_LED_6_LS;
    logic GPIO_LED_7_LS;

    byte rx_byte;

    // =========================================================================
    // DUT
    // =========================================================================

    qu_control_top #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .STEP_HZ    (5)
    ) dut (
        .clk_125mhz_p(clk_125mhz_p),
        .clk_125mhz_n(clk_125mhz_n),

        .USB_UART_TX(USB_UART_TX),
        .USB_UART_RX(USB_UART_RX),

        .CPU_RESET(CPU_RESET),

        .GPIO_LED_0_LS(GPIO_LED_0_LS),
        .GPIO_LED_1_LS(GPIO_LED_1_LS),
        .GPIO_LED_2_LS(GPIO_LED_2_LS),
        .GPIO_LED_3_LS(GPIO_LED_3_LS),
        .GPIO_LED_4_LS(GPIO_LED_4_LS),
        .GPIO_LED_5_LS(GPIO_LED_5_LS),
        .GPIO_LED_6_LS(GPIO_LED_6_LS),
        .GPIO_LED_7_LS(GPIO_LED_7_LS)
    );

    // =========================================================================
    // Differential clock generation
    // =========================================================================

    initial begin
        clk_125mhz_p = 1'b0;
        clk_125mhz_n = 1'b1;
        forever begin
            #(CLK_PERIOD/2);
            clk_125mhz_p = ~clk_125mhz_p;
            clk_125mhz_n = ~clk_125mhz_n;
        end
    end

    // =========================================================================
    // UART RX stimulus from host into FPGA
    // Keep host TX idle high since we are only watching FPGA transmit.
    // =========================================================================

    initial begin
        USB_UART_TX = 1'b1;
    end

    // =========================================================================
    // UART byte receiver for FPGA TX line
    // 8N1, LSB first
    // =========================================================================

    task automatic uart_recv_byte(output byte data);
        int i;
        reg [7:0] tmp;
        begin
            tmp = 8'h00;

            // Wait for start bit
            @(negedge USB_UART_RX);

            // Sample in the middle of each bit
            #(BIT_PERIOD + (BIT_PERIOD/2));
            for (i = 0; i < 8; i++) begin
                tmp[i] = USB_UART_RX;
                #(BIT_PERIOD);
            end

            // Stop bit
            if (USB_UART_RX !== 1'b1) begin
                $error("UART stop bit was not high");
            end

            data = tmp;

            // Move past stop bit center if needed
            #(BIT_PERIOD/2);
        end
    endtask

    // =========================================================================
    // Timeout guard
    // =========================================================================

    initial begin
        #(500us);
        $fatal(1, "Timeout waiting for first UART byte from DUT");
    end

    // =========================================================================
    // Main test
    // =========================================================================

    initial begin
        CPU_RESET = 1'b1;

        // Hold reset for a few clocks
        repeat (10) @(posedge clk_125mhz_p);
        CPU_RESET = 1'b0;

        $display("[%0t] Released reset", $time);

        uart_recv_byte(rx_byte);

        $display("[%0t] First UART byte = 0x%02h (%s)",
                 $time,
                 rx_byte,
                 (rx_byte >= 8'h20 && rx_byte <= 8'h7e) ? {rx_byte} : ".");

        if (rx_byte !== "{") begin
            $fatal(1, "Expected first UART byte to be '{', got 0x%02h", rx_byte);
        end

        $display("[%0t] PASS: DUT transmitted '{' as first UART byte", $time);
        $finish;
    end

    // =========================================================================
    // Extra debug output
    // =========================================================================

    always @(posedge dut.u_init_loader.init_done_pulse) begin
        $display("[%0t] init_done_pulse", $time);
    end

    always @(posedge dut.u_instr_sequencer.formatter_start) begin
        $display("[%0t] formatter_start", $time);
    end

    always @(posedge dut.u_cmd_formatter.done_pulse) begin
        $display("[%0t] formatter_done", $time);
    end

endmodule
