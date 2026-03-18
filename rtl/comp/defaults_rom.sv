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
            // Instr 0: ACCUM_CLEAR before |0> calibration
            // ============================================================

            6: begin
                instr_v.opcode    = OP_ACCUM_CLEAR;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd0;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 1: WAIT_RESET for |0> calibration loop
            // ============================================================

            7: begin
                instr_v.opcode    = OP_WAIT_RESET;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd1;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 2: MEASURE cfg 0 for |0> calibration loop
            // ============================================================

            8: begin
                instr_v.opcode    = OP_MEASURE;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd2;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 3: ACCUM measured I_avg / Q_avg into calibration sums
            // ============================================================

            9: begin
                instr_v.opcode    = OP_ACCUM;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd3;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 4: LOOP |0> calibration body for 3 total passes
            // operand[19:8] = 2, operand[7:0] = target instruction addr 1
            // ============================================================

            10: begin
                instr_v.opcode    = OP_LOOP;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'h00201;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd4;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 5: ACCUM_AVG and store result to |0> refs
            // operand[1:0] = 2'd1
            // ============================================================

            11: begin
                instr_v.opcode    = OP_ACCUM_AVG;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd1;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd5;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 6: ACCUM_CLEAR before |1> calibration
            // ============================================================

            12: begin
                instr_v.opcode    = OP_ACCUM_CLEAR;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd6;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 7: WAIT_RESET for |1> calibration loop
            // ============================================================

            13: begin
                instr_v.opcode    = OP_WAIT_RESET;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd7;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 8: PLAY cfg 1 for |1> calibration loop
            // ============================================================

            14: begin
                instr_v.opcode    = OP_PLAY;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd1;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd8;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 9: MEASURE cfg 1 for |1> calibration loop
            // ============================================================

            15: begin
                instr_v.opcode    = OP_MEASURE;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd1;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd9;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 10: ACCUM measured I_avg / Q_avg into calibration sums
            // ============================================================

            16: begin
                instr_v.opcode    = OP_ACCUM;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd10;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 11: LOOP |1> calibration body for 3 total passes
            // operand[19:8] = 2, operand[7:0] = target instruction addr 7
            // ============================================================

            17: begin
                instr_v.opcode    = OP_LOOP;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'h00207;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd11;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 12: ACCUM_AVG and store result to |1> refs
            // operand[1:0] = 2'd2
            // ============================================================

            18: begin
                instr_v.opcode    = OP_ACCUM_AVG;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd2;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd12;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 13: WAIT_RESET before test sequence
            // ============================================================

            19: begin
                instr_v.opcode    = OP_WAIT_RESET;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd13;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 14: PLAY cfg 0
            // ============================================================

            20: begin
                instr_v.opcode    = OP_PLAY;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd14;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 15: WAIT 100
            // ============================================================

            21: begin
                instr_v.opcode    = OP_WAIT;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd100;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd15;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 16: PLAY cfg 2
            // ============================================================

            22: begin
                instr_v.opcode    = OP_PLAY;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd2;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd16;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 17: MEASURE cfg 0
            // ============================================================

            23: begin
                instr_v.opcode    = OP_MEASURE;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd17;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // Instr 18: END
            // ============================================================

            24: begin
                instr_v.opcode    = OP_END;
                instr_v.flags     = 4'd0;
                instr_v.cfg_index = 4'd0;
                instr_v.operand   = 20'd0;

                rom_word_r.op      = INIT_OP_INSTR;
                rom_word_r.addr    = 8'd18;
                rom_word_r.payload = InitPayloadWidth'(instr_v);
            end

            // ============================================================
            // End of init stream
            // ============================================================

            25: begin
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
