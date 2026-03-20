//------------------------------------------------------------------------------
// PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
//------------------------------------------------------------------------------
// Copyright (C) 2026 Sean Sandone
// SPDX-License-Identifier: AGPL-3.0-or-later
// Please see the LICENSE file for details.
// WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
//------------------------------------------------------------------------------

module leds #(
    parameter int CLK_FREQ_HZ = 125_000_000,
    parameter int unsigned STEP_HZ = 5
)(
    input  logic clk,
    input  logic rst_sync_n,

    input  logic uart_txd_mon,
    input  logic uart_rxd_mon,

    output logic GPIO_LED_0_LS,
    output logic GPIO_LED_1_LS,
    output logic GPIO_LED_2_LS,
    output logic GPIO_LED_3_LS,
    output logic GPIO_LED_4_LS,
    output logic GPIO_LED_5_LS,
    output logic GPIO_LED_6_LS,
    output logic GPIO_LED_7_LS
);

    `ifdef SIM
        localparam int unsigned TickDiv = 100;
    `else
        localparam int unsigned TickDiv = (CLK_FREQ_HZ / STEP_HZ);
    `endif

    logic [$clog2(TickDiv)-1:0] tick_cnt;
    logic tick;

    logic shifting_left;
    logic [5:0] led_c;

    assign tick = (tick_cnt == TickDiv - 1);

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
                        shifting_left <= 1'b0;
                        led_c         <= {1'b0, led_c[5:1]};
                    end else begin
                        led_c <= {led_c[4:0], 1'b0};
                    end
                end else begin
                    if (led_c[0]) begin
                        shifting_left <= 1'b1;
                        led_c         <= {led_c[4:0], 1'b0};
                    end else begin
                        led_c <= {1'b0, led_c[5:1]};
                    end
                end
            end else begin
                tick_cnt <= tick_cnt + 1'b1;
            end
        end
    end

    assign GPIO_LED_0_LS = led_c[0];
    assign GPIO_LED_1_LS = led_c[1];
    assign GPIO_LED_2_LS = led_c[2];
    assign GPIO_LED_3_LS = led_c[3];
    assign GPIO_LED_4_LS = led_c[4];
    assign GPIO_LED_5_LS = led_c[5];
    assign GPIO_LED_6_LS = uart_txd_mon;
    assign GPIO_LED_7_LS = uart_rxd_mon;

endmodule
