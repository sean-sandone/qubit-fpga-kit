//------------------------------------------------------------------------------
// PROJECT: Quantum Computing FPGA Qubit Controller & Test Environment
//------------------------------------------------------------------------------
// Copyright (C) 2026 Sean Sandone
// SPDX-License-Identifier: AGPL-3.0-or-later
// Please see the LICENSE file for details.
// WEBSITE: https://github.com/sean-sandone/qubit-fpga-kit
//------------------------------------------------------------------------------

module write_reg_rx (
    input  logic clk,
    input  logic rst_sync_n,
    input  logic enable,

    input  logic       rx_byte_valid,
    input  logic [7:0] rx_byte,

    output logic                  req_valid,
    input  logic                  req_accept,
    output rtl_pkg::reg_wr_kind_t req_kind,

    output logic                          control_start_exp,
    output logic                          control_soft_reset,
    output logic                          control_read_all,
    output logic [31:0]                   reset_wait_cycles_data,

    output logic [rtl_pkg::PlayCfgAw-1:0] play_cfg_addr,
    output rtl_pkg::play_cfg_t            play_cfg_data,

    output logic [rtl_pkg::MeasCfgAw-1:0] measure_cfg_addr,
    output rtl_pkg::measure_cfg_t         measure_cfg_data,

    output logic [rtl_pkg::InstrAw-1:0]   instr_addr,
    output rtl_pkg::instr_t               instr_data
);

    import rtl_pkg::*;

    typedef enum logic [5:0] {
        RxStateSync0         = 6'd0,
        RxStateSync1         = 6'd1,
        RxStateType          = 6'd2,

        RxStateControlFlags  = 6'd3,

        RxStateResetWait0    = 6'd4,
        RxStateResetWait1    = 6'd5,
        RxStateResetWait2    = 6'd6,
        RxStateResetWait3    = 6'd7,

        RxStatePlayAddr      = 6'd8,
        RxStatePlayAmp0      = 6'd9,
        RxStatePlayAmp1      = 6'd10,
        RxStatePlayPhase0    = 6'd11,
        RxStatePlayPhase1    = 6'd12,
        RxStatePlayDuration0 = 6'd13,
        RxStatePlayDuration1 = 6'd14,
        RxStatePlayDuration2 = 6'd15,
        RxStatePlayDuration3 = 6'd16,
        RxStatePlaySigma0    = 6'd17,
        RxStatePlaySigma1    = 6'd18,
        RxStatePlaySigma2    = 6'd19,
        RxStatePlaySigma3    = 6'd20,
        RxStatePlayPad0      = 6'd21,
        RxStatePlayPad1      = 6'd22,
        RxStatePlayPad2      = 6'd23,
        RxStatePlayPad3      = 6'd24,
        RxStatePlayDetune0   = 6'd25,
        RxStatePlayDetune1   = 6'd26,
        RxStatePlayDetune2   = 6'd27,
        RxStatePlayDetune3   = 6'd28,
        RxStatePlayEnv       = 6'd29,

        RxStateMeasAddr      = 6'd30,
        RxStateMeasCount0    = 6'd31,
        RxStateMeasCount1    = 6'd32,
        RxStateMeasReadout0  = 6'd33,
        RxStateMeasReadout1  = 6'd34,
        RxStateMeasReadout2  = 6'd35,
        RxStateMeasReadout3  = 6'd36,
        RxStateMeasRingup0   = 6'd37,
        RxStateMeasRingup1   = 6'd38,
        RxStateMeasRingup2   = 6'd39,
        RxStateMeasRingup3   = 6'd40,

        RxStateInstrAddr     = 6'd41,
        RxStateInstrWord0    = 6'd42,
        RxStateInstrWord1    = 6'd43,
        RxStateInstrWord2    = 6'd44,
        RxStateInstrWord3    = 6'd45,

        RxStateWaitAccept    = 6'd46
    } rx_state_t;

    rx_state_t state_r;

    reg_wr_kind_t req_kind_r;

    logic control_start_exp_r;
    logic control_soft_reset_r;
    logic control_read_all_r;
    logic [31:0] reset_wait_cycles_data_r;

    logic [PlayCfgAw-1:0] play_cfg_addr_r;
    play_cfg_t            play_cfg_data_r;

    logic [MeasCfgAw-1:0] measure_cfg_addr_r;
    measure_cfg_t         measure_cfg_data_r;

    logic [InstrAw-1:0]   instr_addr_r;
    instr_t               instr_data_r;
    logic [31:0]          instr_word_r;

    always_ff @(posedge clk) begin
        if (!rst_sync_n) begin
            state_r                  <= RxStateSync0;
            req_valid                <= 1'b0;
            req_kind_r               <= REG_WR_KIND_NONE;
            control_start_exp_r      <= 1'b0;
            control_soft_reset_r     <= 1'b0;
            control_read_all_r       <= 1'b0;
            reset_wait_cycles_data_r <= '0;
            play_cfg_addr_r          <= '0;
            play_cfg_data_r          <= '0;
            measure_cfg_addr_r       <= '0;
            measure_cfg_data_r       <= '0;
            instr_addr_r             <= '0;
            instr_data_r             <= '0;
            instr_word_r             <= '0;
        end else begin
            if (req_valid && req_accept) begin
                req_valid  <= 1'b0;
                req_kind_r <= REG_WR_KIND_NONE;
                state_r    <= RxStateSync0;
            end else if (!req_valid) begin
                if (!enable) begin
                    state_r <= RxStateSync0;
                end else begin
                    unique case (state_r)
                        RxStateSync0: if (rx_byte_valid && (rx_byte == RegWrSync0)) begin
                            state_r <= RxStateSync1;
                        end

                        RxStateSync1: if (rx_byte_valid) begin
                            if (rx_byte == RegWrSync1) begin
                                state_r <= RxStateType;
                            end else if (rx_byte == RegWrSync0) begin
                                state_r <= RxStateSync1;
                            end else begin
                                state_r <= RxStateSync0;
                            end
                        end

                        RxStateType: if (rx_byte_valid) begin
                            control_start_exp_r <= 1'b0;
                            control_soft_reset_r <= 1'b0;
                            control_read_all_r <= 1'b0;
                            play_cfg_data_r <= '0;
                            measure_cfg_data_r <= '0;
                            instr_word_r <= '0;

                            unique case (rx_byte)
                                RegWrTypeControl:    state_r <= RxStateControlFlags;
                                RegWrTypeResetWait:  state_r <= RxStateResetWait0;
                                RegWrTypePlayCfg:    state_r <= RxStatePlayAddr;
                                RegWrTypeMeasureCfg: state_r <= RxStateMeasAddr;
                                RegWrTypeInstr:      state_r <= RxStateInstrAddr;
                                default:             state_r <= RxStateSync0;
                            endcase
                        end

                        RxStateControlFlags: if (rx_byte_valid) begin
                            control_start_exp_r <= rx_byte[RegWrControlBitStartExp];
                            control_soft_reset_r <= rx_byte[RegWrControlBitSoftReset];
                            control_read_all_r <= rx_byte[RegWrControlBitReadAll];
                            req_kind_r <= REG_WR_KIND_CONTROL;
                            req_valid  <= 1'b1;
                            state_r    <= RxStateWaitAccept;
                        end

                        RxStateResetWait0: if (rx_byte_valid) begin
                            reset_wait_cycles_data_r[7:0] <= rx_byte;
                            state_r <= RxStateResetWait1;
                        end

                        RxStateResetWait1: if (rx_byte_valid) begin
                            reset_wait_cycles_data_r[15:8] <= rx_byte;
                            state_r <= RxStateResetWait2;
                        end

                        RxStateResetWait2: if (rx_byte_valid) begin
                            reset_wait_cycles_data_r[23:16] <= rx_byte;
                            state_r <= RxStateResetWait3;
                        end

                        RxStateResetWait3: if (rx_byte_valid) begin
                            reset_wait_cycles_data_r[31:24] <= rx_byte;
                            req_kind_r <= REG_WR_KIND_RESET_WAIT;
                            req_valid  <= 1'b1;
                            state_r    <= RxStateWaitAccept;
                        end

                        RxStatePlayAddr: if (rx_byte_valid) begin
                            play_cfg_addr_r <= rx_byte[PlayCfgAw-1:0];
                            state_r <= RxStatePlayAmp0;
                        end

                        RxStatePlayAmp0: if (rx_byte_valid) begin
                            play_cfg_data_r.amp_q8_8[7:0] <= rx_byte;
                            state_r <= RxStatePlayAmp1;
                        end

                        RxStatePlayAmp1: if (rx_byte_valid) begin
                            play_cfg_data_r.amp_q8_8[15:8] <= rx_byte;
                            state_r <= RxStatePlayPhase0;
                        end

                        RxStatePlayPhase0: if (rx_byte_valid) begin
                            play_cfg_data_r.phase_q8_8[7:0] <= rx_byte;
                            state_r <= RxStatePlayPhase1;
                        end

                        RxStatePlayPhase1: if (rx_byte_valid) begin
                            play_cfg_data_r.phase_q8_8[15:8] <= rx_byte;
                            state_r <= RxStatePlayDuration0;
                        end

                        RxStatePlayDuration0: if (rx_byte_valid) begin
                            play_cfg_data_r.duration_ns[7:0] <= rx_byte;
                            state_r <= RxStatePlayDuration1;
                        end

                        RxStatePlayDuration1: if (rx_byte_valid) begin
                            play_cfg_data_r.duration_ns[15:8] <= rx_byte;
                            state_r <= RxStatePlayDuration2;
                        end

                        RxStatePlayDuration2: if (rx_byte_valid) begin
                            play_cfg_data_r.duration_ns[23:16] <= rx_byte;
                            state_r <= RxStatePlayDuration3;
                        end

                        RxStatePlayDuration3: if (rx_byte_valid) begin
                            play_cfg_data_r.duration_ns[31:24] <= rx_byte;
                            state_r <= RxStatePlaySigma0;
                        end

                        RxStatePlaySigma0: if (rx_byte_valid) begin
                            play_cfg_data_r.sigma_ns[7:0] <= rx_byte;
                            state_r <= RxStatePlaySigma1;
                        end

                        RxStatePlaySigma1: if (rx_byte_valid) begin
                            play_cfg_data_r.sigma_ns[15:8] <= rx_byte;
                            state_r <= RxStatePlaySigma2;
                        end

                        RxStatePlaySigma2: if (rx_byte_valid) begin
                            play_cfg_data_r.sigma_ns[23:16] <= rx_byte;
                            state_r <= RxStatePlaySigma3;
                        end

                        RxStatePlaySigma3: if (rx_byte_valid) begin
                            play_cfg_data_r.sigma_ns[31:24] <= rx_byte;
                            state_r <= RxStatePlayPad0;
                        end

                        RxStatePlayPad0: if (rx_byte_valid) begin
                            play_cfg_data_r.pad_ns[7:0] <= rx_byte;
                            state_r <= RxStatePlayPad1;
                        end

                        RxStatePlayPad1: if (rx_byte_valid) begin
                            play_cfg_data_r.pad_ns[15:8] <= rx_byte;
                            state_r <= RxStatePlayPad2;
                        end

                        RxStatePlayPad2: if (rx_byte_valid) begin
                            play_cfg_data_r.pad_ns[23:16] <= rx_byte;
                            state_r <= RxStatePlayPad3;
                        end

                        RxStatePlayPad3: if (rx_byte_valid) begin
                            play_cfg_data_r.pad_ns[31:24] <= rx_byte;
                            state_r <= RxStatePlayDetune0;
                        end

                        RxStatePlayDetune0: if (rx_byte_valid) begin
                            play_cfg_data_r.detune_hz[7:0] <= rx_byte;
                            state_r <= RxStatePlayDetune1;
                        end

                        RxStatePlayDetune1: if (rx_byte_valid) begin
                            play_cfg_data_r.detune_hz[15:8] <= rx_byte;
                            state_r <= RxStatePlayDetune2;
                        end

                        RxStatePlayDetune2: if (rx_byte_valid) begin
                            play_cfg_data_r.detune_hz[23:16] <= rx_byte;
                            state_r <= RxStatePlayDetune3;
                        end

                        RxStatePlayDetune3: if (rx_byte_valid) begin
                            play_cfg_data_r.detune_hz[31:24] <= rx_byte;
                            state_r <= RxStatePlayEnv;
                        end

                        RxStatePlayEnv: if (rx_byte_valid) begin
                            play_cfg_data_r.envelope <= envelope_t'(rx_byte[3:0]);
                            req_kind_r <= REG_WR_KIND_PLAY_CFG;
                            req_valid  <= 1'b1;
                            state_r    <= RxStateWaitAccept;
                        end

                        RxStateMeasAddr: if (rx_byte_valid) begin
                            measure_cfg_addr_r <= rx_byte[MeasCfgAw-1:0];
                            state_r <= RxStateMeasCount0;
                        end

                        RxStateMeasCount0: if (rx_byte_valid) begin
                            measure_cfg_data_r.n_readout[7:0] <= rx_byte;
                            state_r <= RxStateMeasCount1;
                        end

                        RxStateMeasCount1: if (rx_byte_valid) begin
                            measure_cfg_data_r.n_readout[15:8] <= rx_byte;
                            state_r <= RxStateMeasReadout0;
                        end

                        RxStateMeasReadout0: if (rx_byte_valid) begin
                            measure_cfg_data_r.readout_ns[7:0] <= rx_byte;
                            state_r <= RxStateMeasReadout1;
                        end

                        RxStateMeasReadout1: if (rx_byte_valid) begin
                            measure_cfg_data_r.readout_ns[15:8] <= rx_byte;
                            state_r <= RxStateMeasReadout2;
                        end

                        RxStateMeasReadout2: if (rx_byte_valid) begin
                            measure_cfg_data_r.readout_ns[23:16] <= rx_byte;
                            state_r <= RxStateMeasReadout3;
                        end

                        RxStateMeasReadout3: if (rx_byte_valid) begin
                            measure_cfg_data_r.readout_ns[31:24] <= rx_byte;
                            state_r <= RxStateMeasRingup0;
                        end

                        RxStateMeasRingup0: if (rx_byte_valid) begin
                            measure_cfg_data_r.ringup_ns[7:0] <= rx_byte;
                            state_r <= RxStateMeasRingup1;
                        end

                        RxStateMeasRingup1: if (rx_byte_valid) begin
                            measure_cfg_data_r.ringup_ns[15:8] <= rx_byte;
                            state_r <= RxStateMeasRingup2;
                        end

                        RxStateMeasRingup2: if (rx_byte_valid) begin
                            measure_cfg_data_r.ringup_ns[23:16] <= rx_byte;
                            state_r <= RxStateMeasRingup3;
                        end

                        RxStateMeasRingup3: if (rx_byte_valid) begin
                            measure_cfg_data_r.ringup_ns[31:24] <= rx_byte;
                            req_kind_r <= REG_WR_KIND_MEASURE_CFG;
                            req_valid  <= 1'b1;
                            state_r    <= RxStateWaitAccept;
                        end

                        RxStateInstrAddr: if (rx_byte_valid) begin
                            instr_addr_r <= rx_byte[InstrAw-1:0];
                            instr_word_r <= '0;
                            state_r <= RxStateInstrWord0;
                        end

                        RxStateInstrWord0: if (rx_byte_valid) begin
                            instr_word_r[7:0] <= rx_byte;
                            state_r <= RxStateInstrWord1;
                        end

                        RxStateInstrWord1: if (rx_byte_valid) begin
                            instr_word_r[15:8] <= rx_byte;
                            state_r <= RxStateInstrWord2;
                        end

                        RxStateInstrWord2: if (rx_byte_valid) begin
                            instr_word_r[23:16] <= rx_byte;
                            state_r <= RxStateInstrWord3;
                        end

                        RxStateInstrWord3: if (rx_byte_valid) begin
                            instr_word_r[31:24] <= rx_byte;
                            instr_data_r <= instr_t'({rx_byte, instr_word_r[23:0]});
                            req_kind_r <= REG_WR_KIND_INSTR;
                            req_valid  <= 1'b1;
                            state_r    <= RxStateWaitAccept;
                        end

                        RxStateWaitAccept: begin
                            state_r <= RxStateWaitAccept;
                        end

                        default: begin
                            state_r <= RxStateSync0;
                        end
                    endcase
                end
            end
        end
    end

    assign req_kind               = req_kind_r;

    assign control_start_exp      = control_start_exp_r;
    assign control_soft_reset     = control_soft_reset_r;
    assign control_read_all       = control_read_all_r;
    assign reset_wait_cycles_data = reset_wait_cycles_data_r;

    assign play_cfg_addr          = play_cfg_addr_r;
    assign play_cfg_data          = play_cfg_data_r;

    assign measure_cfg_addr       = measure_cfg_addr_r;
    assign measure_cfg_data       = measure_cfg_data_r;

    assign instr_addr             = instr_addr_r;
    assign instr_data             = instr_data_r;

endmodule
