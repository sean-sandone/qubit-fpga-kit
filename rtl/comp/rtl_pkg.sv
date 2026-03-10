package rtl_pkg;

    // ----------------------------
    // Packet / command definitions
    // Starter definitions for the formal RTL structure.
    // These are not yet fully used by the current demo sender.
    // ----------------------------
    typedef enum logic [7:0] {
        CMD_NOP      = 8'h00,
        CMD_PLAY     = 8'h01,
        CMD_MEASURE  = 8'h02,
        CMD_RESET    = 8'h03,
        CMD_PING     = 8'h04
    } cmd_type_t;

    typedef enum logic [3:0] {
        ENV_SQUARE = 4'd0,
        ENV_GAUSS  = 4'd1
    } envelope_t;

    typedef enum logic [1:0] {
        UART_TX_IDLE    = 2'd0,
        UART_TX_PRESENT = 2'd1,
        UART_TX_ADVANCE = 2'd2,
        UART_TX_DONE    = 2'd3
    } uart_tx_state_t;

    typedef struct packed {
        logic [15:0] amp_q8_8;
        logic [15:0] phase_q8_8;
        logic [31:0] duration_cycles;
        logic [31:0] sigma_cycles;
        logic [31:0] pad_cycles;
        envelope_t   envelope;
    } play_cfg_t;

    typedef struct packed {
        logic [15:0] sample_count;
        logic [31:0] duration_cycles;
    } measure_cfg_t;

    localparam int unsigned MsgLen = 102;

endpackage
