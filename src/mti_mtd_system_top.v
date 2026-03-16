//***************************************
//
//        Filename: mti_mtd_system_top.v
//        Author: Koala
//        Description:
//        Create: 2026-3-11
//        Last Modified: 2026-3-16
//
//***************************************

`timescale 1ns/1ps

module mti_mtd_system_top #(
    parameter integer DATA_W    = 32,
    parameter integer RANGE_NUM = 128,
    parameter integer PULSE_NUM = 128,
    parameter integer RANGE_W   = 13,
    parameter integer PULSE_W   = 9,
    parameter integer CH_W      = 2,
    parameter integer ADDR_W    = 14
)(
    input  wire                     sys_clk,
    input  wire                     sys_rst_n,

    // ------------------------------------------------------------------------
    // config
    // ------------------------------------------------------------------------
    input  wire [1:0]               mti_mode_i,
    input  wire                     auto_mti_en_i,
    input  wire [32:0]              clutter_th_low_i,
    input  wire [32:0]              clutter_th_high_i,
    input  wire [8:0]               fft_len_i,
    input  wire [1:0]               win_type_i,
    input  wire                     fft_fwd_inv_i,
    input  wire [7:0]               fft_scale_sch_i,

    // ------------------------------------------------------------------------
    // front-end input stream (pulse-major)
    // ------------------------------------------------------------------------
    input  wire                     in_valid_i,
    output wire                     in_ready_o,
    input  wire                     in_last_i,
    input  wire [DATA_W-1:0]        in_data_i,
    input  wire [RANGE_W-1:0]       in_range_idx_i,
    input  wire [PULSE_W-1:0]       in_pulse_idx_i,
    input  wire [CH_W-1:0]          in_ch_id_i,

    // ------------------------------------------------------------------------
    // final output stream
    // ------------------------------------------------------------------------
    output wire                     out_valid_o,
    input  wire                     out_ready_i,
    output wire                     out_last_o,
    output wire [DATA_W-1:0]        out_data_o,
    output wire [RANGE_W-1:0]       out_range_idx_o,
    output wire [PULSE_W-1:0]       out_dopp_idx_o,
    output wire [CH_W-1:0]          out_ch_id_o
);

    // ------------------------------------------------------------------------
    // localparams
    // ------------------------------------------------------------------------
    localparam MTI_BYPASS = 2'b00;

    // ------------------------------------------------------------------------
    // buffer -> core_chain interconnect
    // ------------------------------------------------------------------------
    wire                     buf_valid;
    wire                     buf_ready;
    wire                     buf_last;
    wire [DATA_W-1:0]        buf_data;
    wire [RANGE_W-1:0]       buf_range_idx;
    wire [PULSE_W-1:0]       buf_pulse_idx;
    wire [CH_W-1:0]          buf_ch_id;

    // ------------------------------------------------------------------------
    // adaptive MTI wires
    // ------------------------------------------------------------------------
    wire                    clutter_wr_en;
    wire [RANGE_W-1:0]      clutter_wr_range_idx;
    wire [32:0]             clutter_wr_value;

    wire                    mode_wr_en;
    wire [RANGE_W-1:0]      mode_wr_range_idx;
    wire [1:0]              mode_wr_value;

    reg  [1:0]              mode_map [0:RANGE_NUM-1];
    wire [1:0]              dyn_mti_mode;

    // ------------------------------------------------------------------------
    // data buffer: pulse-major -> range-major
    // ------------------------------------------------------------------------
    data_pingpong_buf #(
        .DATA_W    (DATA_W),
        .RANGE_NUM (RANGE_NUM),
        .PULSE_NUM (PULSE_NUM),
        .RANGE_W   (RANGE_W),
        .PULSE_W   (PULSE_W),
        .CH_W      (CH_W),
        .ADDR_W    (ADDR_W)
    ) u_data_pingpong_buf (
        .sys_clk         (sys_clk),
        .sys_rst_n       (sys_rst_n),

        .in_valid_i      (in_valid_i),
        .in_ready_o      (in_ready_o),
        .in_last_i       (in_last_i),
        .in_data_i       (in_data_i),
        .in_range_idx_i  (in_range_idx_i),
        .in_pulse_idx_i  (in_pulse_idx_i),
        .in_ch_id_i      (in_ch_id_i),

        .out_valid_o     (buf_valid),
        .out_ready_i     (buf_ready),
        .out_last_o      (buf_last),
        .out_data_o      (buf_data),
        .out_range_idx_o (buf_range_idx),
        .out_pulse_idx_o (buf_pulse_idx),
        .out_ch_id_o     (buf_ch_id)
    );

    // ------------------------------------------------------------------------
    // mode map update
    // range_idx here is assumed to be local range id: 0 ~ RANGE_NUM-1
    // ------------------------------------------------------------------------
    integer mi;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            for (mi = 0; mi < RANGE_NUM; mi = mi + 1)
                mode_map[mi] <= MTI_BYPASS;
        end
        else if (mode_wr_en && (mode_wr_range_idx < RANGE_NUM)) begin
            mode_map[mode_wr_range_idx] <= mode_wr_value;
        end
    end

    assign dyn_mti_mode = (auto_mti_en_i && (buf_range_idx < RANGE_NUM)) ?
                          mode_map[buf_range_idx] : mti_mode_i;

    // ------------------------------------------------------------------------
    // MTI + Window + FFT + Pack
    // ------------------------------------------------------------------------
    core_chain_top u_core_chain_top (
        .sys_clk          (sys_clk),
        .sys_rst_n        (sys_rst_n),

        .mti_mode_i       (dyn_mti_mode),
        .fft_len_i        (fft_len_i),
        .win_type_i       (win_type_i),
        .fft_fwd_inv_i    (fft_fwd_inv_i),
        .fft_scale_sch_i  (fft_scale_sch_i),

        .in_valid_i       (buf_valid),
        .in_ready_o       (buf_ready),
        .in_last_i        (buf_last),
        .in_data_i        (buf_data),
        .in_range_idx_i   (buf_range_idx),
        .in_pulse_idx_i   (buf_pulse_idx),
        .in_ch_id_i       (buf_ch_id),

        .out_valid_o      (out_valid_o),
        .out_ready_i      (out_ready_i),
        .out_last_o       (out_last_o),
        .out_data_o       (out_data_o),
        .out_range_idx_o  (out_range_idx_o),
        .out_dopp_idx_o   (out_dopp_idx_o),
        .out_ch_id_o      (out_ch_id_o)
    );

    // ------------------------------------------------------------------------
    // clutter estimator: observe final FFT output stream
    // only uses dopp_idx==0 as clutter estimate
    // ------------------------------------------------------------------------
    clutter_estimator #(
        .DATA_W  (DATA_W),
        .RANGE_W (RANGE_W),
        .DOPP_W  (PULSE_W),
        .PWR_W   (33)
    ) u_clutter_estimator (
        .sys_clk                (sys_clk),
        .sys_rst_n              (sys_rst_n),

        .in_valid_i             (out_valid_o),
        .in_ready_i             (out_ready_i),
        .in_last_i              (out_last_o),
        .in_data_i              (out_data_o),
        .in_range_idx_i         (out_range_idx_o),
        .in_dopp_idx_i          (out_dopp_idx_o),

        .clutter_wr_en_o        (clutter_wr_en),
        .clutter_wr_range_idx_o (clutter_wr_range_idx),
        .clutter_wr_value_o     (clutter_wr_value)
    );

    // ------------------------------------------------------------------------
    // mode select
    // ------------------------------------------------------------------------
    mti_mode_sel #(
        .RANGE_W (RANGE_W),
        .PWR_W   (33)
    ) u_mti_mode_sel (
        .sys_clk                (sys_clk),
        .sys_rst_n              (sys_rst_n),

        .clutter_wr_en_i        (clutter_wr_en),
        .clutter_wr_range_idx_i (clutter_wr_range_idx),
        .clutter_wr_value_i     (clutter_wr_value),

        .th_low_i               (clutter_th_low_i),
        .th_high_i              (clutter_th_high_i),

        .mode_wr_en_o           (mode_wr_en),
        .mode_wr_range_idx_o    (mode_wr_range_idx),
        .mode_wr_value_o        (mode_wr_value)
    );

`ifndef SYNTHESIS
always @(posedge sys_clk) begin
    if (sys_rst_n && buf_valid && buf_ready) begin
        $display("[%0t] BUF2CORE: range=%0d pulse=%0d last=%0d dyn_mti_mode=%0d",
                 $time, buf_range_idx, buf_pulse_idx, buf_last, dyn_mti_mode);
    end

    if (sys_rst_n && clutter_wr_en) begin
        $display("[%0t] CLUTTER_EST: range=%0d dc_power=%0d",
                 $time, clutter_wr_range_idx, clutter_wr_value);
    end

    if (sys_rst_n && mode_wr_en) begin
        $display("[%0t] MODE_SEL: range=%0d mode=%0d",
                 $time, mode_wr_range_idx, mode_wr_value);
    end
end
`endif

endmodule