module defaults_rom (
    input  logic [rtl_pkg::InitRomAw-1:0] rom_addr,
    output rtl_pkg::init_rom_word_t       rom_word
);

    import rtl_pkg::*;

    init_rom_word_t rom_word_r;

    play_cfg_t    play_cfg_v;
    measure_cfg_t meas_cfg_v;
    instr_t       instr_v;

    always_comb begin
        rom_word_r = '0;
        play_cfg_v = '0;
        meas_cfg_v = '0;
        instr_v    = '0;

        unique case (rom_addr)

            // ============================================================
            // Play config 0
            // ============================================================

            0: begin
                play_cfg_v.amp_q8_8        = 16'h0100; // 1.0
                play_cfg_v.phase_q8_8      = 16'h0000; // 0.0
                play_cfg_v.duration_cycles = 32'd25;
                play_cfg_v.sigma_cycles    = 32'd6;
                play_cfg_v.pad_cycles      = 32'd25;
                play_cfg_v.detune_hz       = 32'd0;
                play_cfg_v.envelope        = EnvGauss;

                rom_word_r.op      = InitOpPlayCfg;
                rom_word_r.addr    = 8'd0;
                rom_word_r.payload = InitPayloadWidth'(play_cfg_v);
            end

            // ============================================================
            // Play config 1
            // ============================================================

            1: begin
                play_cfg_v.amp_q8_8        = 16'h0080; // 0.5
                play_cfg_v.phase_q8_8      = 16'h0100; // placeholder
                play_cfg_v.duration_cycles = 32'd25;
                play_cfg_v.sigma_cycles    = 32'd6;
                play_cfg_v.pad_cycles      = 32'd25;
                play_cfg_v.detune_hz       = 32'd0;
                play_cfg_v.envelope        = EnvGauss;

                rom_word_r.op      = InitOpPlayCfg;
                rom_word_r.addr    = 8'd1;
                rom_word_r.payload = InitPayloadWidth'(play_cfg_v);
            end

            // ============================================================
            // Measure config 0
            // ============================================================

            2: begin
                meas_cfg_v.n_readout         = 16'd64;
                meas_cfg_v.readout_cycles    = 32'd128;
                meas_cfg_v.ringup_frac_q1_15 = 16'h4000; // 0.5

                rom_word_r.op      = InitOpMeasCfg;
                rom_word_r.addr    = 8'd0;
                rom_word_r.payload = InitPayloadWidth'(meas_cfg_v);
            end

            // ============================================================
            // Instr 0: PLAY cfg 0
            // ============================================================

            3: begin
                instr_v.opcode    = OpPlay;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = InitOpInstr;
                rom_word_r.addr    = 8'd0;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 1: WAIT 100
            // ============================================================

            4: begin
                instr_v.opcode    = OpWait;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd100;

                rom_word_r.op      = InitOpInstr;
                rom_word_r.addr    = 8'd1;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 2: PLAY cfg 1
            // ============================================================

            5: begin
                instr_v.opcode    = OpPlay;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd1;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = InitOpInstr;
                rom_word_r.addr    = 8'd2;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 3: MEASURE cfg 0
            // ============================================================

            6: begin
                instr_v.opcode    = OpMeasure;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = InitOpInstr;
                rom_word_r.addr    = 8'd3;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 4: END
            // ============================================================

            7: begin
                instr_v.opcode    = OpEnd;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = InitOpInstr;
                rom_word_r.addr    = 8'd4;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // End of init stream
            // ============================================================

            8: begin
                rom_word_r.op      = InitOpEnd;
                rom_word_r.addr    = 8'd0;
                rom_word_r.payload = '0;
            end

            default: begin
                rom_word_r.op      = InitOpEnd;
                rom_word_r.addr    = 8'd0;
                rom_word_r.payload = '0;
            end
        endcase
    end

    assign rom_word = rom_word_r;

endmodule
