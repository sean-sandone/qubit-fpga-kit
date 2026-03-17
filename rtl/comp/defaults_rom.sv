//------------------------------------------------------------------------------
// PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
//------------------------------------------------------------------------------
// AUTHORS: Sean Sandone
// WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
//------------------------------------------------------------------------------

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
                play_cfg_v.amp_q8_8    = 16'h0100; // 1.0
                play_cfg_v.phase_q8_8  = 16'h0000; // 0.0
                play_cfg_v.duration_ns = 32'd200;
                play_cfg_v.sigma_ns    = 32'd30;
                play_cfg_v.pad_ns      = 32'd200;
                play_cfg_v.detune_hz   = 32'd0;
                play_cfg_v.envelope    = ENV_GAUSS;

                rom_word_r.op      = INIT_OP_PLAY_CFG;
                rom_word_r.addr    = 8'd0;
                rom_word_r.payload = InitPayloadWidth'(play_cfg_v);
            end

            // ============================================================
            // Play config 1 - candidate stronger |1> prep pulse
            // ============================================================

            1: begin
                play_cfg_v.amp_q8_8    = 16'h0330; // 3.1875 - intentionally strong for testing
                play_cfg_v.phase_q8_8  = 16'h0000;
                play_cfg_v.duration_ns = 32'd200;
                play_cfg_v.sigma_ns    = 32'd30;
                play_cfg_v.pad_ns      = 32'd200;
                play_cfg_v.detune_hz   = 32'd0;
                play_cfg_v.envelope    = ENV_GAUSS;

                rom_word_r.op      = INIT_OP_PLAY_CFG;
                rom_word_r.addr    = 8'd1;
                rom_word_r.payload = InitPayloadWidth'(play_cfg_v);
            end

            // ============================================================
            // Play config 2
            // ============================================================

            2: begin
                play_cfg_v.amp_q8_8    = 16'h0080; // 0.5
                play_cfg_v.phase_q8_8  = 16'h0100; // placeholder
                play_cfg_v.duration_ns = 32'd200;
                play_cfg_v.sigma_ns    = 32'd30;
                play_cfg_v.pad_ns      = 32'd200;
                play_cfg_v.detune_hz   = 32'd0;
                play_cfg_v.envelope    = ENV_GAUSS;

                rom_word_r.op      = INIT_OP_PLAY_CFG;
                rom_word_r.addr    = 8'd2;
                rom_word_r.payload = InitPayloadWidth'(play_cfg_v);
            end

            // ============================================================
            // Measure config 0
            // ============================================================

            3: begin
                meas_cfg_v.n_readout  = 16'd64;
                meas_cfg_v.readout_ns = 32'd1024;
                meas_cfg_v.ringup_ns  = 32'd512;

                rom_word_r.op      = INIT_OP_MEAS_CFG;
                rom_word_r.addr    = 8'd0;
                rom_word_r.payload = InitPayloadWidth'(meas_cfg_v);
            end

            // ============================================================
            // Measure config 1
            // ============================================================

            4: begin
                meas_cfg_v.n_readout  = 16'd64;
                meas_cfg_v.readout_ns = 32'd1024;
                meas_cfg_v.ringup_ns  = 32'd256; // shorter ringup

                rom_word_r.op      = INIT_OP_MEAS_CFG;
                rom_word_r.addr    = 8'd1;
                rom_word_r.payload = InitPayloadWidth'(meas_cfg_v);
            end

            // ============================================================
            // Default reset-wait register preload
            // ============================================================

            5: begin
                rom_word_r.op            = INIT_OP_RESET_WAIT;
                rom_word_r.addr          = 8'd0;
                rom_word_r.payload[31:0] = 32'd1000;
            end

            // ============================================================
            // Instr 0: WAIT_RESET for |0> calibration shot 0
            // ============================================================

            6: begin
                instr_v.opcode    = OP_WAIT_RESET;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd0;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 1: MEASURE cfg 0 for |0> calibration shot 0
            // ============================================================

            7: begin
                instr_v.opcode    = OP_MEASURE;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd1;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 2: WAIT_RESET for |0> calibration shot 1
            // ============================================================

            8: begin
                instr_v.opcode    = OP_WAIT_RESET;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd2;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 3: MEASURE cfg 0 for |0> calibration shot 1
            // ============================================================

            9: begin
                instr_v.opcode    = OP_MEASURE;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd3;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 4: WAIT_RESET for |0> calibration shot 2
            // ============================================================

            10: begin
                instr_v.opcode    = OP_WAIT_RESET;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd4;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 5: MEASURE cfg 0 for |0> calibration shot 2
            // ============================================================

            11: begin
                instr_v.opcode    = OP_MEASURE;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd5;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 6: WAIT_RESET for |1> calibration shot 0
            // ============================================================

            12: begin
                instr_v.opcode    = OP_WAIT_RESET;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd6;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 7: PLAY cfg 1 for |1> calibration shot 0
            // ============================================================

            13: begin
                instr_v.opcode    = OP_PLAY;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd1;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd7;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 8: MEASURE cfg 1 for |1> calibration shot 0
            // ============================================================

            14: begin
                instr_v.opcode    = OP_MEASURE;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd1;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd8;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 9: WAIT_RESET for |1> calibration shot 1
            // ============================================================

            15: begin
                instr_v.opcode    = OP_WAIT_RESET;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd9;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 10: PLAY cfg 1 for |1> calibration shot 1
            // ============================================================

            16: begin
                instr_v.opcode    = OP_PLAY;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd1;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd10;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 11: MEASURE cfg 1 for |1> calibration shot 1
            // ============================================================

            17: begin
                instr_v.opcode    = OP_MEASURE;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd1;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd11;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 12: WAIT_RESET for |1> calibration shot 2
            // ============================================================

            18: begin
                instr_v.opcode    = OP_WAIT_RESET;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd12;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 13: PLAY cfg 1 for |1> calibration shot 2
            // ============================================================

            19: begin
                instr_v.opcode    = OP_PLAY;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd1;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd13;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 14: MEASURE cfg 1 for |1> calibration shot 2
            // ============================================================

            20: begin
                instr_v.opcode    = OP_MEASURE;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd1;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd14;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 15: WAIT_RESET before test sequence
            // ============================================================

            21: begin
                instr_v.opcode    = OP_WAIT_RESET;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd15;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 16: PLAY cfg 0
            // ============================================================

            22: begin
                instr_v.opcode    = OP_PLAY;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd16;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 17: WAIT 100
            // ============================================================

            23: begin
                instr_v.opcode    = OP_WAIT;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd100;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd17;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 18: PLAY cfg 2
            // ============================================================

            24: begin
                instr_v.opcode    = OP_PLAY;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd2;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd18;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 19: MEASURE cfg 0
            // ============================================================

            25: begin
                instr_v.opcode    = OP_MEASURE;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd19;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 20: END
            // ============================================================

            26: begin
                instr_v.opcode    = OP_END;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd20;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // End of init stream
            // ============================================================

            27: begin
                rom_word_r.op      = INIT_OP_END;
                rom_word_r.addr    = 8'd0;
                rom_word_r.payload = '0;
            end

            default: begin
                rom_word_r.op      = INIT_OP_END;
                rom_word_r.addr    = 8'd0;
                rom_word_r.payload = '0;
            end
        endcase
    end

    assign rom_word = rom_word_r;

endmodule
