`timescale 1ns/1ps

module mti_mode_sel #(
    parameter integer RANGE_W = 13,
    parameter integer PWR_W   = 33
)(
    input  wire                     sys_clk,
    input  wire                     sys_rst_n,

    input  wire                     clutter_wr_en_i,
    input  wire [RANGE_W-1:0]       clutter_wr_range_idx_i,
    input  wire [PWR_W-1:0]         clutter_wr_value_i,

    input  wire [PWR_W-1:0]         th_low_i,
    input  wire [PWR_W-1:0]         th_high_i,

    output reg                      mode_wr_en_o,
    output reg  [RANGE_W-1:0]       mode_wr_range_idx_o,
    output reg  [1:0]               mode_wr_value_o
);

    localparam MTI_BYPASS = 2'b00;
    localparam MTI_2PULSE = 2'b01;
    localparam MTI_3PULSE = 2'b10;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            mode_wr_en_o        <= 1'b0;
            mode_wr_range_idx_o <= {RANGE_W{1'b0}};
            mode_wr_value_o     <= MTI_BYPASS;
        end
        else begin
            mode_wr_en_o <= 1'b0;

            if (clutter_wr_en_i) begin
                mode_wr_en_o        <= 1'b1;
                mode_wr_range_idx_o <= clutter_wr_range_idx_i;

                if (clutter_wr_value_i < th_low_i)
                    mode_wr_value_o <= MTI_BYPASS;
                else if (clutter_wr_value_i < th_high_i)
                    mode_wr_value_o <= MTI_2PULSE;
                else
                    mode_wr_value_o <= MTI_3PULSE;
            end
        end
    end

endmodule