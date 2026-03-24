//------------------------------------------------------------------------------
// PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
//------------------------------------------------------------------------------
// Copyright (C) 2026 Sean Sandone
// SPDX-License-Identifier: AGPL-3.0-or-later
// Please see the LICENSE file for details.
// WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
//------------------------------------------------------------------------------

module register_dump_tx (
    input  logic clk,
    input  logic rst_sync_n,

    input  logic start,

    input  logic        start_exp,
    input  logic        soft_reset_req,
    input  logic [31:0] reset_wait_cycles,
    input  logic        play_cfg_any_valid,
    input  logic        measure_cfg_any_valid,
    input  logic        instr_any_valid,
    input  logic        seq_busy,
    input  logic        seq_done_sticky,

    input  logic [15:0]        cal_sample_count,
    input  logic signed [15:0] cal_i_avg,
    input  logic signed [15:0] cal_q_avg,
    input  logic signed [15:0] cal_i0_ref,
    input  logic signed [15:0] cal_q0_ref,
    input  logic signed [15:0] cal_i1_ref,
    input  logic signed [15:0] cal_q1_ref,
    input  logic signed [15:0] cal_i_threshold,
    input  logic               cal_state_polarity,
    input  logic               cal_i0q0_valid,
    input  logic               cal_i1q1_valid,
    input  logic               cal_threshold_valid,
    input  logic               meas_state,
    input  logic               meas_state_valid,

    output logic [rtl_pkg::PlayCfgAw-1:0] dump_rd_play_cfg_addr,
    input  rtl_pkg::play_cfg_t            dump_rd_play_cfg_data,
    input  logic                          dump_rd_play_cfg_valid,

    output logic [rtl_pkg::MeasCfgAw-1:0] dump_rd_measure_cfg_addr,
    input  rtl_pkg::measure_cfg_t         dump_rd_measure_cfg_data,
    input  logic                          dump_rd_measure_cfg_valid,

    output logic [rtl_pkg::InstrAw-1:0]   dump_rd_instr_addr,
    input  rtl_pkg::instr_t               dump_rd_instr_data,
    input  logic                          dump_rd_instr_valid,

    output logic [7:0] tx_data,
    output logic       tx_valid,
    input  logic       tx_ready,

    output logic       busy,
    output logic       done_pulse
);

    import rtl_pkg::*;

    localparam int unsigned PlayCfgWordsPerEntry = (($bits(play_cfg_t)    + 31) / 32);
    localparam int unsigned MeasCfgWordsPerEntry = (($bits(measure_cfg_t) + 31) / 32);
    localparam int unsigned PacketLen            = 9;

    typedef enum logic [2:0] {
        DumpStateIdle   = 3'd0,
        DumpStateScalar = 3'd1,
        DumpStatePlay   = 3'd2,
        DumpStateMeas   = 3'd3,
        DumpStateInstr  = 3'd4,
        DumpStateDone   = 3'd5
    } dump_state_t;

    dump_state_t state_r;

    logic        load_record_r;
    logic [3:0]  packet_byte_idx_r;
    logic [7:0]  record_group_r;
    logic [7:0]  record_index_r;
    logic [31:0] record_data_r;

    logic [7:0]           scalar_idx_r;
    logic [PlayCfgAw-1:0] play_idx_r;
    logic [2:0]           play_word_idx_r;
    logic                 play_send_valid_r;
    logic [MeasCfgAw-1:0] meas_idx_r;
    logic [1:0]           meas_word_idx_r;
    logic                 meas_send_valid_r;
    logic [InstrAw-1:0]   instr_idx_r;
    logic                 instr_send_valid_r;

    logic [31:0] scalar_data;
    logic [7:0]  play_group;
    logic [31:0] play_data_word;
    logic [7:0]  meas_group;
    logic [31:0] meas_data_word;

    logic [$bits(play_cfg_t)-1:0]    dump_play_cfg_flat;
    logic [$bits(measure_cfg_t)-1:0] dump_measure_cfg_flat;
    logic [$bits(instr_t)-1:0]       dump_instr_flat;

    assign dump_play_cfg_flat    = dump_rd_play_cfg_data;
    assign dump_measure_cfg_flat = dump_rd_measure_cfg_data;
    assign dump_instr_flat       = dump_rd_instr_data;

    always_comb begin
        unique case (scalar_idx_r)
            8'd0:  scalar_data = reset_wait_cycles;
            8'd1:  scalar_data = {31'd0, start_exp};
            8'd2:  scalar_data = {31'd0, soft_reset_req};
            8'd3:  scalar_data = {31'd0, seq_busy};
            8'd4:  scalar_data = {31'd0, seq_done_sticky};
            8'd5:  scalar_data = {31'd0, play_cfg_any_valid};
            8'd6:  scalar_data = {31'd0, measure_cfg_any_valid};
            8'd7:  scalar_data = {31'd0, instr_any_valid};
            8'd8:  scalar_data = {16'd0, cal_sample_count};
            8'd9:  scalar_data = {{16{cal_i_avg[15]}}, cal_i_avg};
            8'd10: scalar_data = {{16{cal_q_avg[15]}}, cal_q_avg};
            8'd11: scalar_data = {{16{cal_i0_ref[15]}}, cal_i0_ref};
            8'd12: scalar_data = {{16{cal_q0_ref[15]}}, cal_q0_ref};
            8'd13: scalar_data = {{16{cal_i1_ref[15]}}, cal_i1_ref};
            8'd14: scalar_data = {{16{cal_q1_ref[15]}}, cal_q1_ref};
            8'd15: scalar_data = {{16{cal_i_threshold[15]}}, cal_i_threshold};
            8'd16: scalar_data = {31'd0, cal_state_polarity};
            8'd17: scalar_data = {31'd0, cal_i0q0_valid};
            8'd18: scalar_data = {31'd0, cal_i1q1_valid};
            8'd19: scalar_data = {31'd0, cal_threshold_valid};
            8'd20: scalar_data = {30'd0, meas_state_valid, meas_state};
            default: scalar_data = 32'd0;
        endcase
    end

    always_comb begin
        unique case (play_word_idx_r)
            3'd0: begin
                play_group     = RegDumpGroupPlayCfg0;
                play_data_word = dump_play_cfg_flat[31:0];
            end
            3'd1: begin
                play_group     = RegDumpGroupPlayCfg1;
                play_data_word = dump_play_cfg_flat[63:32];
            end
            3'd2: begin
                play_group     = RegDumpGroupPlayCfg2;
                play_data_word = dump_play_cfg_flat[95:64];
            end
            3'd3: begin
                play_group     = RegDumpGroupPlayCfg3;
                play_data_word = dump_play_cfg_flat[127:96];
            end
            3'd4: begin
                play_group     = RegDumpGroupPlayCfg4;
                play_data_word = dump_play_cfg_flat[159:128];
            end
            default: begin
                play_group     = RegDumpGroupPlayCfg5;
                play_data_word = {28'd0, dump_play_cfg_flat[$bits(play_cfg_t)-1 -: 4]};
            end
        endcase
    end

    always_comb begin
        unique case (meas_word_idx_r)
            2'd0: begin
                meas_group     = RegDumpGroupMeasCfg0;
                meas_data_word = dump_measure_cfg_flat[31:0];
            end
            2'd1: begin
                meas_group     = RegDumpGroupMeasCfg1;
                meas_data_word = dump_measure_cfg_flat[63:32];
            end
            default: begin
                meas_group     = RegDumpGroupMeasCfg2;
                meas_data_word = {16'd0, dump_measure_cfg_flat[$bits(measure_cfg_t)-1 -: 16]};
            end
        endcase
    end

    assign dump_rd_play_cfg_addr    = play_idx_r;
    assign dump_rd_measure_cfg_addr = meas_idx_r;
    assign dump_rd_instr_addr       = instr_idx_r;

    assign busy = (state_r != DumpStateIdle);
    assign tx_valid = busy && !load_record_r && (state_r != DumpStateDone);

    always_comb begin
        unique case (packet_byte_idx_r)
            4'd0: tx_data = RegDumpSync0;
            4'd1: tx_data = RegDumpSync1;
            4'd2: tx_data = RegDumpType;
            4'd3: tx_data = record_group_r;
            4'd4: tx_data = record_index_r;
            4'd5: tx_data = record_data_r[7:0];
            4'd6: tx_data = record_data_r[15:8];
            4'd7: tx_data = record_data_r[23:16];
            default: tx_data = record_data_r[31:24];
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
            state_r            <= DumpStateIdle;
            load_record_r      <= 1'b0;
            packet_byte_idx_r  <= 4'd0;
            record_group_r     <= 8'd0;
            record_index_r     <= 8'd0;
            record_data_r      <= 32'd0;
            scalar_idx_r       <= 8'd0;
            play_idx_r         <= '0;
            play_word_idx_r    <= 3'd0;
            play_send_valid_r  <= 1'b0;
            meas_idx_r         <= '0;
            meas_word_idx_r    <= 2'd0;
            meas_send_valid_r  <= 1'b0;
            instr_idx_r        <= '0;
            instr_send_valid_r <= 1'b0;
            done_pulse         <= 1'b0;
        end else begin
            done_pulse <= 1'b0;

            case (state_r)
                DumpStateIdle: begin
                    packet_byte_idx_r <= 4'd0;
                    load_record_r <= 1'b0;
                    if (start) begin
                        state_r            <= DumpStateScalar;
                        load_record_r      <= 1'b1;
                        scalar_idx_r       <= 8'd0;
                        play_idx_r         <= '0;
                        play_word_idx_r    <= 3'd0;
                        play_send_valid_r  <= 1'b0;
                        meas_idx_r         <= '0;
                        meas_word_idx_r    <= 2'd0;
                        meas_send_valid_r  <= 1'b0;
                        instr_idx_r        <= '0;
                        instr_send_valid_r <= 1'b0;
                    end
                end

                DumpStateDone: begin
                    state_r       <= DumpStateIdle;
                    load_record_r <= 1'b0;
                    done_pulse    <= 1'b1;
                end

                default: begin
                    if (load_record_r) begin
                        packet_byte_idx_r <= 4'd0;
                        load_record_r <= 1'b0;

                        unique case (state_r)
                            DumpStateScalar: begin
                                record_group_r <= RegDumpGroupScalar;
                                record_index_r <= scalar_idx_r;
                                record_data_r  <= scalar_data;
                            end

                            DumpStatePlay: begin
                                if (play_send_valid_r) begin
                                    record_group_r <= RegDumpGroupPlayValid;
                                    record_index_r <= play_idx_r;
                                    record_data_r  <= {31'd0, dump_rd_play_cfg_valid};
                                end else begin
                                    record_group_r <= play_group;
                                    record_index_r <= play_idx_r;
                                    record_data_r  <= play_data_word;
                                end
                            end

                            DumpStateMeas: begin
                                if (meas_send_valid_r) begin
                                    record_group_r <= RegDumpGroupMeasValid;
                                    record_index_r <= meas_idx_r;
                                    record_data_r  <= {31'd0, dump_rd_measure_cfg_valid};
                                end else begin
                                    record_group_r <= meas_group;
                                    record_index_r <= meas_idx_r;
                                    record_data_r  <= meas_data_word;
                                end
                            end

                            DumpStateInstr: begin
                                if (instr_send_valid_r) begin
                                    record_group_r <= RegDumpGroupInstrValid;
                                    record_index_r <= instr_idx_r;
                                    record_data_r  <= {31'd0, dump_rd_instr_valid};
                                end else begin
                                    record_group_r <= RegDumpGroupInstr;
                                    record_index_r <= instr_idx_r;
                                    record_data_r  <= dump_instr_flat[31:0];
                                end
                            end

                            default: begin
                            end
                        endcase
                    end else if (tx_valid && tx_ready) begin
                        if (packet_byte_idx_r == (PacketLen - 1)) begin
                            packet_byte_idx_r <= 4'd0;

                            unique case (state_r)
                                DumpStateScalar: begin
                                    if (scalar_idx_r == (RegDumpScalarCount - 1)) begin
                                        state_r           <= DumpStatePlay;
                                        play_idx_r        <= '0;
                                        play_word_idx_r   <= 3'd0;
                                        play_send_valid_r <= 1'b0;
                                        load_record_r     <= 1'b1;
                                    end else begin
                                        scalar_idx_r  <= scalar_idx_r + 8'd1;
                                        load_record_r <= 1'b1;
                                    end
                                end

                                DumpStatePlay: begin
                                    if (play_send_valid_r) begin
                                        play_send_valid_r <= 1'b0;
                                        if (play_idx_r == (PlayCfgDepth - 1)) begin
                                            state_r           <= DumpStateMeas;
                                            meas_idx_r        <= '0;
                                            meas_word_idx_r   <= 2'd0;
                                            meas_send_valid_r <= 1'b0;
                                            load_record_r     <= 1'b1;
                                        end else begin
                                            play_idx_r       <= play_idx_r + 1'b1;
                                            play_word_idx_r  <= 3'd0;
                                            load_record_r    <= 1'b1;
                                        end
                                    end else if (play_word_idx_r == (PlayCfgWordsPerEntry - 1)) begin
                                        play_send_valid_r <= 1'b1;
                                        load_record_r <= 1'b1;
                                    end else begin
                                        play_word_idx_r <= play_word_idx_r + 3'd1;
                                        load_record_r <= 1'b1;
                                    end
                                end

                                DumpStateMeas: begin
                                    if (meas_send_valid_r) begin
                                        meas_send_valid_r <= 1'b0;
                                        if (meas_idx_r == (MeasCfgDepth - 1)) begin
                                            state_r            <= DumpStateInstr;
                                            instr_idx_r        <= '0;
                                            instr_send_valid_r <= 1'b0;
                                            load_record_r      <= 1'b1;
                                        end else begin
                                            meas_idx_r      <= meas_idx_r + 1'b1;
                                            meas_word_idx_r <= 2'd0;
                                            load_record_r   <= 1'b1;
                                        end
                                    end else if (meas_word_idx_r == (MeasCfgWordsPerEntry - 1)) begin
                                        meas_send_valid_r <= 1'b1;
                                        load_record_r <= 1'b1;
                                    end else begin
                                        meas_word_idx_r <= meas_word_idx_r + 2'd1;
                                        load_record_r <= 1'b1;
                                    end
                                end

                                DumpStateInstr: begin
                                    if (instr_send_valid_r) begin
                                        instr_send_valid_r <= 1'b0;
                                        if (instr_idx_r == (InstrDepth - 1)) begin
                                            state_r <= DumpStateDone;
                                        end else begin
                                            instr_idx_r   <= instr_idx_r + 1'b1;
                                            load_record_r <= 1'b1;
                                        end
                                    end else begin
                                        instr_send_valid_r <= 1'b1;
                                        load_record_r <= 1'b1;
                                    end
                                end

                                default: begin
                                    state_r <= DumpStateDone;
                                end
                            endcase
                        end else begin
                            packet_byte_idx_r <= packet_byte_idx_r + 4'd1;
                        end
                    end
                end
            endcase
        end
    end

endmodule
