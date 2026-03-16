//***************************************
//
//        Filename: fft_ip_wrap.v
//        Author: Koala
//        Description:
//        Create: 2026-3-11
//        Last Modified: 2026-3-11
//
//***************************************
module fft_ip_wrap (
    input               sys_clk,
    input               sys_rst_n,

    // fft config
    input       [8:0]   fft_len_i,          // support 64 / 128
    input               fft_fwd_inv_i,      // 1: forward FFT
    input       [7:0]   fft_scale_sch_i,    // runtime scaling schedule

    // input stream
    input               in_valid_i,
    output              in_ready_o,
    input               in_last_i,
    input       [31:0]  in_data_i,          // {IM[15:0], RE[15:0]}
    input       [12:0]  in_range_idx_i,
    input       [8:0]   in_pulse_idx_i,
    input       [1:0]   in_ch_id_i,

    // output stream
    output              out_valid_o,
    input               out_ready_i,
    output              out_last_o,
    output      [31:0]  out_data_o,         // {IM[15:0], RE[15:0]}
    output      [12:0]  out_range_idx_o,
    output      [8:0]   out_dopp_idx_o,
    output      [1:0]   out_ch_id_o
);

localparam ST_IDLE      = 2'd0;
localparam ST_SEND_CFG  = 2'd1;
localparam ST_SEND_DATA = 2'd2;
localparam ST_RECV_DATA = 2'd3;

reg [1:0] state_r;

reg [12:0] frame_range_idx_r;
reg [1:0]  frame_ch_id_r;
reg [8:0]  out_cnt_r;

wire [4:0] nfft_code_w;
assign nfft_code_w = (fft_len_i == 9'd64 ) ? 5'd6 :
                     (fft_len_i == 9'd128) ? 5'd7 :
                                              5'd7;

wire [23:0] cfg_word_w;
assign cfg_word_w = {7'd0, fft_scale_sch_i, fft_fwd_inv_i, 3'd0, nfft_code_w};

wire                s_axis_config_tready;
reg                 s_axis_config_tvalid;
reg [23:0]          s_axis_config_tdata;

wire                s_axis_data_tready;
wire                m_axis_data_tvalid;
wire [31:0]         m_axis_data_tdata;
wire                m_axis_data_tlast;

wire                event_frame_started;
wire                event_tlast_unexpected;
wire                event_tlast_missing;
wire                event_status_channel_halt;
wire                event_data_in_channel_halt;
wire                event_data_out_channel_halt;

wire cfg_fire;
wire in_fire;
wire out_fire;

assign cfg_fire = s_axis_config_tvalid & s_axis_config_tready;
assign in_fire  = (state_r == ST_SEND_DATA) & in_valid_i & s_axis_data_tready;
assign out_fire = (state_r == ST_RECV_DATA) & m_axis_data_tvalid & out_ready_i;

assign in_ready_o = (state_r == ST_SEND_DATA) & s_axis_data_tready;

wire [1:0] state_n =
    (state_r == ST_IDLE)      ? (in_valid_i ? ST_SEND_CFG : ST_IDLE) :
    (state_r == ST_SEND_CFG)  ? (cfg_fire ? ST_SEND_DATA : ST_SEND_CFG) :
    (state_r == ST_SEND_DATA) ? ((in_fire & in_last_i) ? ST_RECV_DATA : ST_SEND_DATA) :
    (state_r == ST_RECV_DATA) ? ((out_fire & m_axis_data_tlast) ? ST_IDLE : ST_RECV_DATA) :
                                ST_IDLE;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
        state_r <= ST_IDLE;
    else
        state_r <= state_n;
end

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        frame_range_idx_r <= 13'd0;
        frame_ch_id_r     <= 2'd0;
    end
    else if ((state_r == ST_IDLE) & in_valid_i) begin
        frame_range_idx_r <= in_range_idx_i;
        frame_ch_id_r     <= in_ch_id_i;
    end
end

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        s_axis_config_tvalid <= 1'b0;
        s_axis_config_tdata  <= 24'd0;
    end
    else begin
        case (state_r)
            ST_SEND_CFG: begin
                s_axis_config_tvalid <= 1'b1;
                s_axis_config_tdata  <= cfg_word_w;
            end
            default: begin
                if (cfg_fire)
                    s_axis_config_tvalid <= 1'b0;
                else if (state_r != ST_SEND_CFG)
                    s_axis_config_tvalid <= 1'b0;
            end
        endcase
    end
end

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        out_cnt_r <= 9'd0;
    end
    else if (state_r == ST_IDLE) begin
        out_cnt_r <= 9'd0;
    end
    else if (out_fire) begin
        if (m_axis_data_tlast)
            out_cnt_r <= 9'd0;
        else
            out_cnt_r <= out_cnt_r + 9'd1;
    end
end

assign out_valid_o      = (state_r == ST_RECV_DATA) & m_axis_data_tvalid;
assign out_last_o       = (state_r == ST_RECV_DATA) ? m_axis_data_tlast : 1'b0;
assign out_data_o       = m_axis_data_tdata;
assign out_range_idx_o  = frame_range_idx_r;
assign out_dopp_idx_o   = out_cnt_r;
assign out_ch_id_o      = frame_ch_id_r;

mtd_fft u_mtd_fft (
    .aclk                       (sys_clk),
    .aresetn                    (sys_rst_n),
    .s_axis_config_tdata        (s_axis_config_tdata),
    .s_axis_config_tvalid       (s_axis_config_tvalid),
    .s_axis_config_tready       (s_axis_config_tready),
    .s_axis_data_tdata          (in_data_i),
    .s_axis_data_tvalid         ((state_r == ST_SEND_DATA) ? in_valid_i : 1'b0),
    .s_axis_data_tready         (s_axis_data_tready),
    .s_axis_data_tlast          (in_last_i),
    .m_axis_data_tdata          (m_axis_data_tdata),
    .m_axis_data_tvalid         (m_axis_data_tvalid),
    .m_axis_data_tready         (out_ready_i),
    .m_axis_data_tlast          (m_axis_data_tlast),
    .event_frame_started        (event_frame_started),
    .event_tlast_unexpected     (event_tlast_unexpected),
    .event_tlast_missing        (event_tlast_missing),
    .event_status_channel_halt  (event_status_channel_halt),
    .event_data_in_channel_halt (event_data_in_channel_halt),
    .event_data_out_channel_halt(event_data_out_channel_halt)
);

endmodule
