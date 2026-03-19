//------------------------------------------------------------------------------
// PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
//------------------------------------------------------------------------------
// AUTHORS: Sean Sandone
// WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
//------------------------------------------------------------------------------

module instr_sequencer (
    input  logic clk,
    input  logic rst_sync_n,

    input  logic init_done,
    input  logic [31:0] reset_wait_cycles,

    output logic [rtl_pkg::InstrAw-1:0]   rd_instr_addr,
    input  rtl_pkg::instr_t               rd_instr_data,

    output logic [rtl_pkg::PlayCfgAw-1:0] rd_play_cfg_addr,
    input  rtl_pkg::play_cfg_t            rd_play_cfg_data,

    output logic [rtl_pkg::MeasCfgAw-1:0] rd_measure_cfg_addr,
    input  rtl_pkg::measure_cfg_t         rd_measure_cfg_data,

    output logic                          formatter_start,
    output logic                          formatter_is_play,
    output logic                          formatter_is_reset,
    output logic [3:0]                    formatter_cfg_index,
    output rtl_pkg::play_cfg_t            formatter_play_cfg,
    output rtl_pkg::measure_cfg_t         formatter_measure_cfg,
    input  logic                          formatter_busy,
    input  logic                          formatter_done_pulse,

    output logic                          measure_start,
    input  logic                          measure_rsp_done_pulse,

    output logic                          cal_accum_clear,
    output logic                          cal_accum_push,
    output logic                          cal_accum_finalize,
    output logic [1:0]                    cal_accum_store_sel,
    input  logic                          cal_accum_done_pulse,

    output logic                          seq_busy,
    output logic                          seq_done_pulse
);

    import rtl_pkg::*;

    typedef enum logic [3:0] {
        SeqStateIdle            = 4'd0,
        SeqStateFetch           = 4'd1,
        SeqStateDecode          = 4'd2,
        SeqStateStartPlay       = 4'd3,
        SeqStateStartMeasure    = 4'd4,
        SeqStateWaitFormat      = 4'd5,
        SeqStateWaitCycles      = 4'd6,
        SeqStateWaitMeasureRsp  = 4'd7,
        SeqStateDone            = 4'd8,
        SeqStateStartReset      = 4'd9,
        SeqStateWaitAccumAvg    = 4'd10
    } seq_state_t;

    seq_state_t state_r;

    logic [InstrAw-1:0] pc_r;
    logic [3:0]         cfg_index_r;
    logic [31:0]        wait_count_r;
    logic               started_r;
    logic               last_was_play_r;
    logic               last_was_reset_r;

    logic               loop_active_r;
    logic [11:0]        loop_count_r;
    logic [InstrAw-1:0] loop_target_r;

    logic [1:0]         cal_accum_store_sel_r;

    assign rd_instr_addr       = pc_r;
    assign rd_play_cfg_addr    = cfg_index_r[PlayCfgAw-1:0];
    assign rd_measure_cfg_addr = cfg_index_r[MeasCfgAw-1:0];

    assign formatter_cfg_index   = cfg_index_r;
    assign formatter_play_cfg    = rd_play_cfg_data;
    assign formatter_measure_cfg = rd_measure_cfg_data;
    assign formatter_is_play     = last_was_play_r;
    assign formatter_is_reset    = last_was_reset_r;
    assign cal_accum_store_sel   = cal_accum_store_sel_r;

    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
            state_r               <= SeqStateIdle;
            pc_r                  <= '0;
            cfg_index_r           <= '0;
            wait_count_r          <= '0;
            started_r             <= 1'b0;
            last_was_play_r       <= 1'b0;
            last_was_reset_r      <= 1'b0;
            formatter_start       <= 1'b0;
            measure_start         <= 1'b0;
            cal_accum_clear       <= 1'b0;
            cal_accum_push        <= 1'b0;
            cal_accum_finalize    <= 1'b0;
            cal_accum_store_sel_r <= CAL_DEST_TEMP;
            seq_done_pulse        <= 1'b0;
            loop_active_r         <= 1'b0;
            loop_count_r          <= '0;
            loop_target_r         <= '0;
        end else begin
            formatter_start    <= 1'b0;
            measure_start      <= 1'b0;
            cal_accum_clear    <= 1'b0;
            cal_accum_push     <= 1'b0;
            cal_accum_finalize <= 1'b0;
            seq_done_pulse     <= 1'b0;

            case (state_r)
                SeqStateIdle: begin
                    if (init_done && !started_r) begin
                        pc_r      <= '0;
                        started_r <= 1'b1;
                        state_r   <= SeqStateFetch;
                    end
                end

                SeqStateFetch: begin
                    state_r <= SeqStateDecode;
                end

                SeqStateDecode: begin
                    unique case (rd_instr_data.opcode)
                        OP_NOP: begin
                            pc_r    <= pc_r + 1'b1;
                            state_r <= SeqStateFetch;
                        end

                        OP_PLAY: begin
                            cfg_index_r      <= rd_instr_data.cfg_index;
                            last_was_play_r  <= 1'b1;
                            last_was_reset_r <= 1'b0;
                            state_r          <= SeqStateStartPlay;
                        end

                        OP_MEASURE: begin
                            cfg_index_r      <= rd_instr_data.cfg_index;
                            last_was_play_r  <= 1'b0;
                            last_was_reset_r <= 1'b0;
                            state_r          <= SeqStateStartMeasure;
                        end

                        OP_WAIT: begin
                            if (rd_instr_data.operand == 20'd0) begin
                                pc_r    <= pc_r + 1'b1;
                                state_r <= SeqStateFetch;
                            end else begin
                                wait_count_r <= {12'd0, rd_instr_data.operand} - 1'b1;
                                state_r      <= SeqStateWaitCycles;
                            end
                        end

                        OP_JUMP: begin
                            pc_r          <= rd_instr_data.operand[InstrAw-1:0];
                            loop_active_r <= 1'b0;
                            state_r       <= SeqStateFetch;
                        end

                        OP_WAIT_RESET: begin
                            cfg_index_r      <= 4'd0;
                            last_was_play_r  <= 1'b0;
                            last_was_reset_r <= 1'b1;
                            state_r          <= SeqStateStartReset;
                        end

                        OP_ACCUM_CLEAR: begin
                            cal_accum_clear <= 1'b1;
                            pc_r            <= pc_r + 1'b1;
                            state_r         <= SeqStateFetch;
                        end

                        OP_ACCUM: begin
                            cal_accum_push <= 1'b1;
                            pc_r           <= pc_r + 1'b1;
                            state_r        <= SeqStateFetch;
                        end

                        OP_ACCUM_AVG: begin
                            cal_accum_store_sel_r <= rd_instr_data.operand[1:0];
                            cal_accum_finalize    <= 1'b1;
                            state_r               <= SeqStateWaitAccumAvg;
                        end

                        OP_LOOP: begin
                            if (!loop_active_r) begin
                                if (rd_instr_data.operand[19:8] == 12'd0) begin
                                    pc_r <= pc_r + 1'b1;
                                end else begin
                                    loop_active_r <= 1'b1;
                                    loop_count_r  <= rd_instr_data.operand[19:8];
                                    loop_target_r <= rd_instr_data.operand[InstrAw-1:0];
                                    pc_r          <= rd_instr_data.operand[InstrAw-1:0];
                                end
                            end else if (loop_count_r > 12'd1) begin
                                loop_count_r <= loop_count_r - 1'b1;
                                pc_r         <= loop_target_r;
                            end else begin
                                loop_active_r <= 1'b0;
                                loop_count_r  <= '0;
                                pc_r          <= pc_r + 1'b1;
                            end

                            state_r <= SeqStateFetch;
                        end

                        OP_END: begin
                            seq_done_pulse <= 1'b1;
                            state_r        <= SeqStateDone;
                        end

                        default: begin
                            pc_r    <= pc_r + 1'b1;
                            state_r <= SeqStateFetch;
                        end
                    endcase
                end

                SeqStateStartPlay: begin
                    if (!formatter_busy) begin
                        formatter_start <= 1'b1;
                        state_r         <= SeqStateWaitFormat;
                    end
                end

                SeqStateStartMeasure: begin
                    if (!formatter_busy) begin
                        formatter_start <= 1'b1;
                        measure_start   <= 1'b1;
                        state_r         <= SeqStateWaitFormat;
                    end
                end

                SeqStateStartReset: begin
                    if (!formatter_busy) begin
                        formatter_start <= 1'b1;
                        state_r         <= SeqStateWaitFormat;
                    end
                end

                SeqStateWaitFormat: begin
                    if (formatter_done_pulse) begin
                        if (last_was_play_r) begin
                            pc_r    <= pc_r + 1'b1;
                            state_r <= SeqStateFetch;
                        end else if (last_was_reset_r) begin
                            if (reset_wait_cycles == 32'd0) begin
                                pc_r    <= pc_r + 1'b1;
                                state_r <= SeqStateFetch;
                            end else begin
                                wait_count_r <= reset_wait_cycles - 1'b1;
                                state_r      <= SeqStateWaitCycles;
                            end
                        end else begin
                            state_r <= SeqStateWaitMeasureRsp;
                        end
                    end
                end

                SeqStateWaitMeasureRsp: begin
                    if (measure_rsp_done_pulse) begin
                        pc_r    <= pc_r + 1'b1;
                        state_r <= SeqStateFetch;
                    end
                end

                SeqStateWaitAccumAvg: begin
                    if (cal_accum_done_pulse) begin
                        pc_r    <= pc_r + 1'b1;
                        state_r <= SeqStateFetch;
                    end
                end

                SeqStateWaitCycles: begin
                    if (wait_count_r == 32'd0) begin
                        pc_r    <= pc_r + 1'b1;
                        state_r <= SeqStateFetch;
                    end else begin
                        wait_count_r <= wait_count_r - 1'b1;
                    end
                end

                SeqStateDone: begin
                    state_r <= SeqStateDone;
                end

                default: begin
                    state_r <= SeqStateIdle;
                end
            endcase
        end
    end

    always_comb begin
        case (state_r)
            SeqStateIdle,
            SeqStateDone: seq_busy = 1'b0;

            default: seq_busy = 1'b1;
        endcase
    end

endmodule
