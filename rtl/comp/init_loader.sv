module init_loader (
    input  logic clk,
    input  logic rst_sync_n,

    // ============================================================
    // ROM interface
    // ============================================================

    output logic [rtl_pkg::InitRomAw-1:0] rom_addr,
    input  rtl_pkg::init_rom_word_t       rom_word,

    // ============================================================
    // Register-bank write interface
    // ============================================================

    output logic                          wr_control,
    output logic                          control_start_exp_in,
    output logic                          control_soft_reset_in,

    output logic                          wr_play_cfg,
    output logic [rtl_pkg::PlayCfgAw-1:0] wr_play_cfg_addr,
    output rtl_pkg::play_cfg_t            wr_play_cfg_data,

    output logic                          wr_measure_cfg,
    output logic [rtl_pkg::MeasCfgAw-1:0] wr_measure_cfg_addr,
    output rtl_pkg::measure_cfg_t         wr_measure_cfg_data,

    output logic                          wr_instr,
    output logic [rtl_pkg::InstrAw-1:0]   wr_instr_addr,
    output rtl_pkg::instr_t               wr_instr_data,

    // ============================================================
    // Status
    // ============================================================

    output logic init_active,
    output logic init_done
);

    import rtl_pkg::*;

    typedef enum logic [1:0] {
        InitStateIdle = 2'd0,
        InitStateRun  = 2'd1,
        InitStateDone = 2'd2
    } init_state_t;

    init_state_t state_r;
    logic [InitRomAw-1:0] rom_addr_r;

    // ============================================================
    // State / address sequencing
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
            if (LoadDefaultsAfterReset) begin
                state_r    <= InitStateRun;
                rom_addr_r <= '0;
            end else begin
                state_r    <= InitStateDone;
                rom_addr_r <= '0;
            end
        end else begin
            case (state_r)
                InitStateIdle: begin
                    state_r    <= InitStateDone;
                    rom_addr_r <= '0;
                end

                InitStateRun: begin
                    if (rom_word.op == InitOpEnd) begin
                        state_r <= InitStateDone;
                    end else begin
                        rom_addr_r <= rom_addr_r + 1'b1;
                    end
                end

                InitStateDone: begin
                    state_r <= InitStateDone;
                end

                default: begin
                    state_r <= InitStateDone;
                end
            endcase
        end
    end

    // ============================================================
    // Decode ROM word into register-bank write strobes
    // ============================================================

    always_comb begin
        rom_addr = rom_addr_r;

        wr_control            = 1'b0;
        control_start_exp_in  = 1'b0;
        control_soft_reset_in = 1'b0;

        wr_play_cfg           = 1'b0;
        wr_play_cfg_addr      = '0;
        wr_play_cfg_data      = '0;

        wr_measure_cfg        = 1'b0;
        wr_measure_cfg_addr   = '0;
        wr_measure_cfg_data   = '0;

        wr_instr              = 1'b0;
        wr_instr_addr         = '0;
        wr_instr_data         = '0;

        init_active           = 1'b0;
        init_done             = 1'b0;

        case (state_r)
            InitStateIdle: begin
                init_active = 1'b0;
                init_done   = 1'b0;
            end

            InitStateRun: begin
                init_active = 1'b1;
                init_done   = 1'b0;

                unique case (rom_word.op)
                    InitOpNop: begin
                    end

                    InitOpPlayCfg: begin
                        wr_play_cfg      = 1'b1;
                        wr_play_cfg_addr = rom_word.addr[PlayCfgAw-1:0];
                        wr_play_cfg_data = play_cfg_t'(rom_word.payload);
                    end

                    InitOpMeasCfg: begin
                        wr_measure_cfg      = 1'b1;
                        wr_measure_cfg_addr = rom_word.addr[MeasCfgAw-1:0];
                        wr_measure_cfg_data = measure_cfg_t'(rom_word.payload);
                    end

                    InitOpInstr: begin
                        wr_instr      = 1'b1;
                        wr_instr_addr = rom_word.addr[InstrAw-1:0];
                        wr_instr_data = instr_t'(rom_word.payload);
                    end

                    InitOpControl: begin
                        wr_control            = 1'b1;
                        control_start_exp_in  = rom_word.payload[0];
                        control_soft_reset_in = rom_word.payload[1];
                    end

                    InitOpEnd: begin
                    end

                    default: begin
                    end
                endcase
            end

            InitStateDone: begin
                init_active = 1'b0;
                init_done   = 1'b1;
            end

            default: begin
                init_active = 1'b0;
                init_done   = 1'b1;
            end
        endcase
    end

endmodule
