//***************************************
//
//        Filename: out_pack.v
//        Author: Koala
//        Description:
//        Create: 2026-3-11
//        Last Modified: 2026-3-16
//
//***************************************

module out_pack (
    input               sys_clk,
    input               sys_rst_n,

    // input stream
    input               in_valid_i,
    output              in_ready_o,
    input               in_last_i,
    input       [31:0]  in_data_i,        // {IM[15:0], RE[15:0]}
    input       [12:0]  in_range_idx_i,
    input       [8:0]   in_dopp_idx_i,
    input       [1:0]   in_ch_id_i,

    // output stream
    output              out_valid_o,
    input               out_ready_i,
    output              out_last_o,
    output      [31:0]  out_data_o,
    output      [12:0]  out_range_idx_o,
    output      [8:0]   out_dopp_idx_o,
    output      [1:0]   out_ch_id_o
);

reg                 out_valid_r;
reg                 out_last_r;
reg     [31:0]      out_data_r;
reg     [12:0]      out_range_idx_r;
reg     [8:0]       out_dopp_idx_r;
reg     [1:0]       out_ch_id_r;

wire out_fire;
wire in_fire;

// single-stage register slice
assign out_fire   = out_valid_r & out_ready_i;
assign in_ready_o = (~out_valid_r) | out_ready_i;
assign in_fire    = in_valid_i & in_ready_o;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        out_valid_r      <= 1'b0;
        out_last_r       <= 1'b0;
        out_data_r       <= 32'd0;
        out_range_idx_r  <= 13'd0;
        out_dopp_idx_r   <= 9'd0;
        out_ch_id_r      <= 2'd0;
    end
    else begin
        if (out_fire)
            out_valid_r <= 1'b0;

        if (in_fire) begin
            out_valid_r      <= 1'b1;
            out_last_r       <= in_last_i;
            out_data_r       <= in_data_i;
            out_range_idx_r  <= in_range_idx_i;
            out_dopp_idx_r   <= in_dopp_idx_i;
            out_ch_id_r      <= in_ch_id_i;
        end
    end
end

assign out_valid_o      = out_valid_r;
assign out_last_o       = out_last_r;
assign out_data_o       = out_data_r;
assign out_range_idx_o  = out_range_idx_r;
assign out_dopp_idx_o   = out_dopp_idx_r;
assign out_ch_id_o      = out_ch_id_r;

endmodule
