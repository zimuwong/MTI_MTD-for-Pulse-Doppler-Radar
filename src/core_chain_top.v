//***************************************
//
//        Filename: core_chain_top.v
//        Author: Koala
//        Description:
//        Create: 2026-3-11
//        Last Modified: 2026-3-16
//
//***************************************

`timescale 1ns/1ps

module core_chain_top (
    input  wire         sys_clk,
    input  wire         sys_rst_n,

    // cfg
    input  wire [1:0]   mti_mode_i,
    input  wire [8:0]   fft_len_i,
    input  wire [1:0]   win_type_i,
    input  wire         fft_fwd_inv_i,
    input  wire [7:0]   fft_scale_sch_i,

    // input stream
    input  wire         in_valid_i,
    output wire         in_ready_o,
    input  wire         in_last_i,
    input  wire [31:0]  in_data_i,
    input  wire [12:0]  in_range_idx_i,
    input  wire [8:0]   in_pulse_idx_i,
    input  wire [1:0]   in_ch_id_i,

    // output stream
    output wire         out_valid_o,
    input  wire         out_ready_i,
    output wire         out_last_o,
    output wire [31:0]  out_data_o,
    output wire [12:0]  out_range_idx_o,
    output wire [8:0]   out_dopp_idx_o,
    output wire [1:0]   out_ch_id_o
);

    // =========================================================================
    // stage 1: MTI
    // =========================================================================
    wire         mti_valid;
    wire         mti_ready;
    wire         mti_last;
    wire [31:0]  mti_data;
    wire [12:0]  mti_range_idx;
    wire [8:0]   mti_pulse_idx;
    wire [1:0]   mti_ch_id;

    mti_core u_mti_core (
        .sys_clk            (sys_clk),
        .sys_rst_n          (sys_rst_n),

        .mti_mode_i         (mti_mode_i),

        .in_valid_i         (in_valid_i),
        .in_ready_o         (in_ready_o),
        .in_last_i          (in_last_i),
        .in_data_i          (in_data_i),
        .in_range_idx_i     (in_range_idx_i),
        .in_pulse_idx_i     (in_pulse_idx_i),
        .in_ch_id_i         (in_ch_id_i),

        .out_valid_o        (mti_valid),
        .out_ready_i        (mti_ready),
        .out_last_o         (mti_last),
        .out_data_o         (mti_data),
        .out_range_idx_o    (mti_range_idx),
        .out_pulse_idx_o    (mti_pulse_idx),
        .out_ch_id_o        (mti_ch_id)
    );

    // =========================================================================
    // stage 2: window
    // =========================================================================
    wire         win_valid;
    wire         win_ready;
    wire         win_last;
    wire [31:0]  win_data;
    wire [12:0]  win_range_idx;
    wire [8:0]   win_pulse_idx;
    wire [1:0]   win_ch_id;

    mtd_win u_mtd_win (
        .sys_clk            (sys_clk),
        .sys_rst_n          (sys_rst_n),

        .win_type_i         (win_type_i),
        .fft_len_i          (fft_len_i),

        .in_valid_i         (mti_valid),
        .in_ready_o         (mti_ready),
        .in_last_i          (mti_last),
        .in_data_i          (mti_data),
        .in_range_idx_i     (mti_range_idx),
        .in_pulse_idx_i     (mti_pulse_idx),
        .in_ch_id_i         (mti_ch_id),

        .out_valid_o        (win_valid),
        .out_ready_i        (win_ready),
        .out_last_o         (win_last),
        .out_data_o         (win_data),
        .out_range_idx_o    (win_range_idx),
        .out_pulse_idx_o    (win_pulse_idx),
        .out_ch_id_o        (win_ch_id)
    );

    // =========================================================================
    // stage 3: FFT
    // =========================================================================
    wire        fft_in_ready;
    wire        fft_valid;
    wire        fft_ready;
    wire        fft_last;
    wire [31:0] fft_data;
    wire [12:0] fft_range_idx;
    wire [8:0]  fft_dopp_idx;
    wire [1:0]  fft_ch_id;

    assign win_ready = fft_in_ready;

    fft_ip_wrap u_fft_ip_wrap (
        .sys_clk            (sys_clk),
        .sys_rst_n          (sys_rst_n),

        .fft_len_i          (fft_len_i),
        .fft_fwd_inv_i      (fft_fwd_inv_i),
        .fft_scale_sch_i    (fft_scale_sch_i),

        .in_valid_i         (win_valid),
        .in_ready_o         (fft_in_ready),
        .in_last_i          (win_last),
        .in_data_i          (win_data),
        .in_range_idx_i     (win_range_idx),
        .in_pulse_idx_i     (win_pulse_idx),
        .in_ch_id_i         (win_ch_id),

        .out_valid_o        (fft_valid),
        .out_ready_i        (fft_ready),
        .out_last_o         (fft_last),
        .out_data_o         (fft_data),
        .out_range_idx_o    (fft_range_idx),
        .out_dopp_idx_o     (fft_dopp_idx),
        .out_ch_id_o        (fft_ch_id)
    );

    // =========================================================================
    // stage 4: output pack
    // =========================================================================
    out_pack u_out_pack (
        .sys_clk            (sys_clk),
        .sys_rst_n          (sys_rst_n),

        .in_valid_i         (fft_valid),
        .in_ready_o         (fft_ready),
        .in_last_i          (fft_last),
        .in_data_i          (fft_data),
        .in_range_idx_i     (fft_range_idx),
        .in_dopp_idx_i      (fft_dopp_idx),
        .in_ch_id_i         (fft_ch_id),

        .out_valid_o        (out_valid_o),
        .out_ready_i        (out_ready_i),
        .out_last_o         (out_last_o),
        .out_data_o         (out_data_o),
        .out_range_idx_o    (out_range_idx_o),
        .out_dopp_idx_o     (out_dopp_idx_o),
        .out_ch_id_o        (out_ch_id_o)
    );

endmodule