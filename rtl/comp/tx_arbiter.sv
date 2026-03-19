//------------------------------------------------------------------------------
// PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
//------------------------------------------------------------------------------
// AUTHORS: Sean Sandone
// WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
//------------------------------------------------------------------------------

module tx_arbiter (
    input  logic clk,
    input  logic rst_sync_n,

    input  logic [7:0] formatter_tx_data,
    input  logic       formatter_tx_valid,
    output logic       formatter_tx_ready,
    input  logic       formatter_busy,
    input  logic       formatter_done_pulse,

    input  logic [7:0] debug_tx_data,
    input  logic       debug_tx_valid,
    output logic       debug_tx_ready,
    input  logic       debug_busy,
    input  logic       debug_done_pulse,

    input  logic       debug_pending,
    output logic       debug_start,

    output logic [7:0] uart_tx_data,
    output logic       uart_tx_valid,
    input  logic       uart_tx_ready
);

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

    assign debug_start = debug_pending && (tx_owner_r == TxOwnerNone);

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

endmodule
