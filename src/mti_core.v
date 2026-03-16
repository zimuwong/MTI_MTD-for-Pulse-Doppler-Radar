//***************************************
//
//        Filename: mti_core.v
//        Author: Koala
//        Description:
//        Create: 2026-3-11 
//        Last Modified: 2026-3-11
//
//***************************************
module mti_core (
    input               sys_clk,
    input               sys_rst_n,

    // mode control
    input       [1:0]   mti_mode_i,      // 2'b00:bypass 2'b01:2-pulse 2'b10:3-pulse

    // input slow-time vector stream
    input               in_valid_i,
    output              in_ready_o,
    input               in_last_i,
    input       [31:0]  in_data_i,       // {Q[15:0], I[15:0]}
    input       [12:0]  in_range_idx_i,
    input       [8:0]   in_pulse_idx_i,
    input       [1:0]   in_ch_id_i,

    // output stream
    output              out_valid_o,
    input               out_ready_i,
    output              out_last_o,
    output      [31:0]  out_data_o,
    output      [12:0]  out_range_idx_o,
    output      [8:0]   out_pulse_idx_o,
    output      [1:0]   out_ch_id_o
);

localparam MTI_BYPASS = 2'b00;
localparam MTI_2PULSE = 2'b01;
localparam MTI_3PULSE = 2'b10;

// -----------------------------------------------------------------------------
// internal handshake
// single-stage output register
// -----------------------------------------------------------------------------
reg                 out_valid_r;
reg                 out_last_r;
reg     [31:0]      out_data_r;
reg     [12:0]      out_range_idx_r;
reg     [8:0]       out_pulse_idx_r;
reg     [1:0]       out_ch_id_r;

wire out_fire;
wire in_fire;

assign out_fire  = out_valid_r & out_ready_i;
assign in_ready_o = (~out_valid_r) | out_ready_i;
assign in_fire   = in_valid_i & in_ready_o;

// -----------------------------------------------------------------------------
// delay registers for one slow-time vector
// only updated when input sample is accepted
// -----------------------------------------------------------------------------
reg signed [15:0] dly1_i;
reg signed [15:0] dly1_q;
reg signed [15:0] dly2_i;
reg signed [15:0] dly2_q;
reg [12:0]        prev_range_idx_r;
reg [1:0]         prev_ch_id_r;
reg               prev_valid_r;

// current input unpack
wire signed [15:0] cur_i;
wire signed [15:0] cur_q;

assign cur_i = in_data_i[15:0];
assign cur_q = in_data_i[31:16];

// Start of a new slow-time vector:
// - pulse index restarts at 0
// - or range/channel changes unexpectedly
// - or no previous accepted sample exists
wire new_vector_start =
    (in_pulse_idx_i == 9'd0) ||
    (!prev_valid_r) ||
    (in_range_idx_i != prev_range_idx_r) ||
    (in_ch_id_i != prev_ch_id_r);

// wider arithmetic for MTI
wire signed [18:0] cur_i_ext  = {{3{cur_i[15]}},  cur_i};
wire signed [18:0] cur_q_ext  = {{3{cur_q[15]}},  cur_q};
wire signed [18:0] dly1_i_ext = {{3{dly1_i[15]}}, dly1_i};
wire signed [18:0] dly1_q_ext = {{3{dly1_q[15]}}, dly1_q};
wire signed [18:0] dly2_i_ext = {{3{dly2_i[15]}}, dly2_i};
wire signed [18:0] dly2_q_ext = {{3{dly2_q[15]}}, dly2_q};

wire signed [18:0] calc_i =
    (mti_mode_i == MTI_BYPASS) ? cur_i_ext :
    (mti_mode_i == MTI_2PULSE) ? ((in_pulse_idx_i == 9'd0) ? 19'sd0 : (cur_i_ext - dly1_i_ext)) :
    (mti_mode_i == MTI_3PULSE) ? ((in_pulse_idx_i <= 9'd1) ? 19'sd0 : (cur_i_ext - (dly1_i_ext <<< 1) + dly2_i_ext)) :
                                 cur_i_ext;

wire signed [18:0] calc_q =
    (mti_mode_i == MTI_BYPASS) ? cur_q_ext :
    (mti_mode_i == MTI_2PULSE) ? ((in_pulse_idx_i == 9'd0) ? 19'sd0 : (cur_q_ext - dly1_q_ext)) :
    (mti_mode_i == MTI_3PULSE) ? ((in_pulse_idx_i <= 9'd1) ? 19'sd0 : (cur_q_ext - (dly1_q_ext <<< 1) + dly2_q_ext)) :
                                 cur_q_ext;

// saturated outputs
wire signed [15:0] sat_i =
    (calc_i > 19'sd32767) ? 16'sh7fff :
    (calc_i < -19'sd32768) ? 16'sh8000 :
    calc_i[15:0];

wire signed [15:0] sat_q =
    (calc_q > 19'sd32767) ? 16'sh7fff :
    (calc_q < -19'sd32768) ? 16'sh8000 :
    calc_q[15:0];

// -----------------------------------------------------------------------------
// sequential logic
// -----------------------------------------------------------------------------
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        out_valid_r      <= 1'b0;
        out_last_r       <= 1'b0;
        out_data_r       <= 32'd0;
        out_range_idx_r  <= 13'd0;
        out_pulse_idx_r  <= 9'd0;
        out_ch_id_r      <= 2'd0;

        dly1_i           <= 16'sd0;
        dly1_q           <= 16'sd0;
        dly2_i           <= 16'sd0;
        dly2_q           <= 16'sd0;
        prev_range_idx_r <= 13'd0;
        prev_ch_id_r     <= 2'd0;
        prev_valid_r     <= 1'b0;
    end
    else begin
        // output valid management
        if (out_fire)
            out_valid_r <= 1'b0;

        if (in_fire) begin
            // register output
            out_valid_r      <= 1'b1;
            out_last_r       <= in_last_i;
            out_data_r       <= {sat_q, sat_i};
            out_range_idx_r  <= in_range_idx_i;
            out_pulse_idx_r  <= in_pulse_idx_i;
            out_ch_id_r      <= in_ch_id_i;

            // update delays for next accepted sample
            // when a new vector starts, clear history first
            if (new_vector_start) begin
                dly2_i <= 16'sd0;
                dly2_q <= 16'sd0;
                dly1_i <= cur_i;
                dly1_q <= cur_q;
            end
            else begin
                dly2_i <= dly1_i;
                dly2_q <= dly1_q;
                dly1_i <= cur_i;
                dly1_q <= cur_q;
            end

            prev_range_idx_r <= in_range_idx_i;
            prev_ch_id_r     <= in_ch_id_i;
            prev_valid_r     <= 1'b1;
        end
    end
end

// -----------------------------------------------------------------------------
// outputs
// -----------------------------------------------------------------------------
assign out_valid_o      = out_valid_r;
assign out_last_o       = out_last_r;
assign out_data_o       = out_data_r;
assign out_range_idx_o  = out_range_idx_r;
assign out_pulse_idx_o  = out_pulse_idx_r;
assign out_ch_id_o      = out_ch_id_r;

endmodule