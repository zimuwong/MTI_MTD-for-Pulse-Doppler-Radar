`timescale 1ns/1ps

module clutter_estimator #(
    parameter integer DATA_W  = 32,
    parameter integer RANGE_W = 13,
    parameter integer DOPP_W  = 9,
    parameter integer PWR_W   = 33
)(
    input  wire                     sys_clk,
    input  wire                     sys_rst_n,

    input  wire                     in_valid_i,
    input  wire                     in_ready_i,
    input  wire                     in_last_i,
    input  wire [DATA_W-1:0]        in_data_i,
    input  wire [RANGE_W-1:0]       in_range_idx_i,
    input  wire [DOPP_W-1:0]        in_dopp_idx_i,

    output reg                      clutter_wr_en_o,
    output reg  [RANGE_W-1:0]       clutter_wr_range_idx_o,
    output reg  [PWR_W-1:0]         clutter_wr_value_o
);

    wire in_fire = in_valid_i & in_ready_i;

    wire signed [15:0] din_i = in_data_i[15:0];
    wire signed [15:0] din_q = in_data_i[31:16];

    wire signed [31:0] ii = din_i * din_i;
    wire signed [31:0] qq = din_q * din_q;
    wire [PWR_W-1:0] power_dc = ii + qq;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            clutter_wr_en_o        <= 1'b0;
            clutter_wr_range_idx_o <= {RANGE_W{1'b0}};
            clutter_wr_value_o     <= {PWR_W{1'b0}};
        end
        else begin
            clutter_wr_en_o <= 1'b0;

            if (in_fire && (in_dopp_idx_i == {DOPP_W{1'b0}})) begin
                clutter_wr_en_o        <= 1'b1;
                clutter_wr_range_idx_o <= in_range_idx_i;
                clutter_wr_value_o     <= power_dc;
            end
        end
    end

endmodule