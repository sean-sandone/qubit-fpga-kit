//------------------------------------------------------------------------------
// PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
//------------------------------------------------------------------------------
// AUTHORS: Sean Sandone
// WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
//------------------------------------------------------------------------------

package rtl_pkg;

    // ============================================================
    // Basic command / opcode definitions
    // ============================================================

    typedef enum logic [3:0] {
        ENV_SQUARE = 4'd0,
        ENV_GAUSS  = 4'd1
    } envelope_t;

    typedef enum logic [3:0] {
        OP_NOP        = 4'd0,
        OP_PLAY       = 4'd1,
        OP_MEASURE    = 4'd2,
        OP_WAIT       = 4'd3,
        OP_END        = 4'd4,
        OP_JUMP       = 4'd5,
        OP_WAIT_RESET = 4'd6
    } opcode_t;

    typedef enum logic [1:0] {
        UART_TX_IDLE    = 2'd0,
        UART_TX_PRESENT = 2'd1,
        UART_TX_ADVANCE = 2'd2,
        UART_TX_DONE    = 2'd3
    } uart_tx_state_t;

    typedef enum logic [2:0] {
        INIT_OP_NOP        = 3'd0,
        INIT_OP_PLAY_CFG   = 3'd1,
        INIT_OP_MEAS_CFG   = 3'd2,
        INIT_OP_INSTR      = 3'd3,
        INIT_OP_CONTROL    = 3'd4,
        INIT_OP_RESET_WAIT = 3'd5,
        INIT_OP_END        = 3'd7
    } init_op_t;

    // ============================================================
    // Memory sizing
    // ============================================================

    localparam int unsigned PlayCfgDepth = 8;
    localparam int unsigned MeasCfgDepth = 4;
    localparam int unsigned InstrDepth   = 32;

    localparam int unsigned PlayCfgAw = (PlayCfgDepth <= 1) ? 1 : $clog2(PlayCfgDepth);
    localparam int unsigned MeasCfgAw = (MeasCfgDepth <= 1) ? 1 : $clog2(MeasCfgDepth);
    localparam int unsigned InstrAw   = (InstrDepth   <= 1) ? 1 : $clog2(InstrDepth);

    localparam bit LoadDefaultsAfterReset = 1'b1;
    localparam int unsigned InitRomDepth  = 32;
    localparam int unsigned InitRomAw     = (InitRomDepth <= 1) ? 1 : $clog2(InitRomDepth);

    // ============================================================
    // Config structures
    // ============================================================

    typedef struct packed {
        logic [15:0] amp_q8_8;
        logic [15:0] phase_q8_8;
        logic [31:0] duration_ns;
        logic [31:0] sigma_ns;
        logic [31:0] pad_ns;
        logic [31:0] detune_hz;
        envelope_t   envelope;
    } play_cfg_t;

    typedef struct packed {
        logic [15:0] n_readout;
        logic [31:0] readout_ns;
        logic [31:0] ringup_ns;
    } measure_cfg_t;

    // ============================================================
    // Instruction format
    // ============================================================

    typedef struct packed {
        opcode_t      opcode;
        logic [3:0]   flags;
        logic [3:0]   cfg_index;
        logic [19:0]  operand;
    } instr_t;

    // ============================================================
    // Default init ROM support
    // ============================================================

    localparam int unsigned InitPayloadWidth = $bits(play_cfg_t);

    typedef struct packed {
        init_op_t                    op;
        logic [7:0]                  addr;
        logic [InitPayloadWidth-1:0] payload;
    } init_rom_word_t;

    // ============================================================
    // UART measure response packet constants
    // ============================================================

    localparam logic [7:0] MeasureRespSync0 = 8'hA5;
    localparam logic [7:0] MeasureRespSync1 = 8'h5A;
    localparam logic [7:0] MeasureRespType  = 8'h02;

    localparam int unsigned MeasureSampleWidth = 16;
    localparam int unsigned MeasureAccumWidth  = 32;
    localparam int unsigned Q2_14FracBits      = 14;

    // ============================================================
    // Legacy demo constant
    // ============================================================

    localparam int unsigned PlayMsgLen = 102;

endpackage
