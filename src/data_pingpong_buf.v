`timescale 1ns/1ps

module data_pingpong_buf #(
    parameter integer DATA_W    = 32,
    parameter integer RANGE_NUM = 128,   // must be power of 2
    parameter integer PULSE_NUM = 128,
    parameter integer RANGE_W   = 13,
    parameter integer PULSE_W   = 9,
    parameter integer CH_W      = 2,
    parameter integer ADDR_W    = 14
)(
    input  wire                     sys_clk,
    input  wire                     sys_rst_n,

    // ------------------------------------------------------------------------
    // input stream (pulse-major)
    // ------------------------------------------------------------------------
    input  wire                     in_valid_i,
    output wire                     in_ready_o,
    input  wire                     in_last_i,
    input  wire [DATA_W-1:0]        in_data_i,
    input  wire [RANGE_W-1:0]       in_range_idx_i,
    input  wire [PULSE_W-1:0]       in_pulse_idx_i,
    input  wire [CH_W-1:0]          in_ch_id_i,

    // ------------------------------------------------------------------------
    // output stream (range-major)
    // ------------------------------------------------------------------------
    output reg                      out_valid_o,
    input  wire                     out_ready_i,
    output reg                      out_last_o,       // last pulse of one range
    output reg  [DATA_W-1:0]        out_data_o,
    output reg  [RANGE_W-1:0]       out_range_idx_o,
    output reg  [PULSE_W-1:0]       out_pulse_idx_o,
    output reg  [CH_W-1:0]          out_ch_id_o
);

    // =========================================================================
    // localparam
    // =========================================================================
    localparam integer RANGE_SHIFT = $clog2(RANGE_NUM);

    // =========================================================================
    // write-side
    // =========================================================================
    reg wr_bank_sel;   // 0: ping, 1: pong

    reg bank_full_ping;
    reg bank_full_pong;

    reg [CH_W-1:0] bank_ch_id_ping;
    reg [CH_W-1:0] bank_ch_id_pong;

    wire in_fire;
    assign in_fire   = in_valid_i & in_ready_o;
    assign in_ready_o = 1'b1;   // minimum version: always accept input

    // input address: pulse-major
    // addr = pulse_idx * RANGE_NUM + range_idx
    wire [ADDR_W-1:0] wr_addr;
    assign wr_addr = (in_pulse_idx_i << RANGE_SHIFT) + in_range_idx_i;

    // =========================================================================
    // read-side control
    // =========================================================================
    reg rd_bank_sel;              // currently selected read bank
    reg reading;                  // read scheduler active

    reg [RANGE_W-1:0] rd_range_idx;
    reg [PULSE_W-1:0] rd_pulse_idx;

    reg [ADDR_W-1:0]  rd_addr_r;
    reg               rd_en_r;

    reg               rd_data_valid_r;    // RAM read latency align (1 cycle)
    reg [RANGE_W-1:0] rd_range_idx_d1;
    reg [PULSE_W-1:0] rd_pulse_idx_d1;
    reg               rd_last_d1;
    reg               rd_bank_last_d1;
    reg [CH_W-1:0]    rd_ch_id_d1;

    reg               clear_bank_pulse;
    reg               clear_bank_sel;     // 0: clear ping, 1: clear pong

    wire out_fire;
    assign out_fire = out_valid_o & out_ready_i;

    // =========================================================================
    // BMG IP interface
    // =========================================================================
    wire                  ram_ping_ena;
    wire [0:0]            ram_ping_wea;
    wire [ADDR_W-1:0]     ram_ping_addra;
    wire [DATA_W-1:0]     ram_ping_dina;
    wire                  ram_ping_enb;
    wire [ADDR_W-1:0]     ram_ping_addrb;
    wire [DATA_W-1:0]     ram_ping_doutb;

    wire                  ram_pong_ena;
    wire [0:0]            ram_pong_wea;
    wire [ADDR_W-1:0]     ram_pong_addra;
    wire [DATA_W-1:0]     ram_pong_dina;
    wire                  ram_pong_enb;
    wire [ADDR_W-1:0]     ram_pong_addrb;
    wire [DATA_W-1:0]     ram_pong_doutb;

    // write side
    assign ram_ping_ena    = (wr_bank_sel == 1'b0) && in_fire;
    assign ram_ping_wea[0] = (wr_bank_sel == 1'b0) && in_fire;
    assign ram_ping_addra  = wr_addr;
    assign ram_ping_dina   = in_data_i;

    assign ram_pong_ena    = (wr_bank_sel == 1'b1) && in_fire;
    assign ram_pong_wea[0] = (wr_bank_sel == 1'b1) && in_fire;
    assign ram_pong_addra  = wr_addr;
    assign ram_pong_dina   = in_data_i;

    // read side
    assign ram_ping_enb   = (rd_bank_sel == 1'b0) && rd_en_r;
    assign ram_ping_addrb = rd_addr_r;

    assign ram_pong_enb   = (rd_bank_sel == 1'b1) && rd_en_r;
    assign ram_pong_addrb = rd_addr_r;

    wire [DATA_W-1:0] rd_data_mux;
    assign rd_data_mux = (rd_bank_sel == 1'b0) ? ram_ping_doutb : ram_pong_doutb;

    // =========================================================================
    // BMG instances
    // =========================================================================
    ram_ping u_ram_ping (
        .clka   (sys_clk),
        .ena    (ram_ping_ena),
        .wea    (ram_ping_wea),
        .addra  (ram_ping_addra),
        .dina   (ram_ping_dina),
        .clkb   (sys_clk),
        .enb    (ram_ping_enb),
        .addrb  (ram_ping_addrb),
        .doutb  (ram_ping_doutb)
    );

    ram_pong u_ram_pong (
        .clka   (sys_clk),
        .ena    (ram_pong_ena),
        .wea    (ram_pong_wea),
        .addra  (ram_pong_addra),
        .dina   (ram_pong_dina),
        .clkb   (sys_clk),
        .enb    (ram_pong_enb),
        .addrb  (ram_pong_addrb),
        .doutb  (ram_pong_doutb)
    );

    // =========================================================================
    // write bank management
    // =========================================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            wr_bank_sel     <= 1'b0;
            bank_full_ping  <= 1'b0;
            bank_full_pong  <= 1'b0;
            bank_ch_id_ping <= {CH_W{1'b0}};
            bank_ch_id_pong <= {CH_W{1'b0}};
        end
        else begin
            // capture bank channel id on writes
         if (in_fire) begin
    if (wr_bank_sel == 1'b0)
        bank_ch_id_ping <= in_ch_id_i;
    else
        bank_ch_id_pong <= in_ch_id_i;

    // use address boundary as the real frame-done condition
    if (wr_addr == (RANGE_NUM * PULSE_NUM - 1)) begin
        if (wr_bank_sel == 1'b0)
            bank_full_ping <= 1'b1;
        else
            bank_full_pong <= 1'b1;

        wr_bank_sel <= ~wr_bank_sel;
    end
end

            // clear only the bank that has just been fully read
            if (clear_bank_pulse) begin
                if (clear_bank_sel == 1'b0)
                    bank_full_ping <= 1'b0;
                else
                    bank_full_pong <= 1'b0;
            end
        end
    end

    // =========================================================================
    // read scheduler
    // =========================================================================
    wire cur_is_last_pulse;
    wire cur_is_last_range;
    wire cur_is_last_bank;

    assign cur_is_last_pulse = (rd_pulse_idx == PULSE_NUM-1);
    assign cur_is_last_range = (rd_range_idx == RANGE_NUM-1);
    assign cur_is_last_bank  = cur_is_last_range && cur_is_last_pulse;

    wire [ADDR_W-1:0] rd_addr_calc;
    assign rd_addr_calc = (rd_pulse_idx << RANGE_SHIFT) + rd_range_idx;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            rd_bank_sel      <= 1'b0;
            reading          <= 1'b0;
            rd_range_idx     <= {RANGE_W{1'b0}};
            rd_pulse_idx     <= {PULSE_W{1'b0}};
            rd_addr_r        <= {ADDR_W{1'b0}};
            rd_en_r          <= 1'b0;

            rd_data_valid_r  <= 1'b0;
            rd_range_idx_d1  <= {RANGE_W{1'b0}};
            rd_pulse_idx_d1  <= {PULSE_W{1'b0}};
            rd_last_d1       <= 1'b0;
            rd_bank_last_d1  <= 1'b0;
            rd_ch_id_d1      <= {CH_W{1'b0}};

            out_valid_o      <= 1'b0;
            out_last_o       <= 1'b0;
            out_data_o       <= {DATA_W{1'b0}};
            out_range_idx_o  <= {RANGE_W{1'b0}};
            out_pulse_idx_o  <= {PULSE_W{1'b0}};
            out_ch_id_o      <= {CH_W{1'b0}};

            clear_bank_pulse <= 1'b0;
            clear_bank_sel   <= 1'b0;
        end
        else begin
            // defaults
            rd_en_r          <= 1'b0;
            clear_bank_pulse <= 1'b0;

            // -------------------------------------------------------------
            // if current output accepted, drop valid
            // -------------------------------------------------------------
            if (out_fire) begin
                out_valid_o <= 1'b0;
                out_last_o  <= 1'b0;
            end

            // -------------------------------------------------------------
            // stage: RAM data return -> output register
            // only load when output register is free
            // -------------------------------------------------------------
            if (rd_data_valid_r && !out_valid_o) begin
                out_valid_o     <= 1'b1;
                out_data_o      <= rd_data_mux;
                out_range_idx_o <= rd_range_idx_d1;
                out_pulse_idx_o <= rd_pulse_idx_d1;
                out_last_o      <= rd_last_d1;
                out_ch_id_o     <= rd_ch_id_d1;

                rd_data_valid_r <= 1'b0;

                // if last sample of whole bank just arrived at output side,
                // stop reading and clear the bank that was read.
                if (rd_bank_last_d1) begin
                    reading          <= 1'b0;
                    clear_bank_pulse <= 1'b1;
                    clear_bank_sel   <= rd_bank_sel;
                    rd_bank_sel      <= ~rd_bank_sel;
                    rd_range_idx     <= {RANGE_W{1'b0}};
                    rd_pulse_idx     <= {PULSE_W{1'b0}};
                end
            end

            // -------------------------------------------------------------
            // idle -> start reading if selected bank is full
            // -------------------------------------------------------------
            if (!reading && !out_valid_o && !rd_data_valid_r) begin
                if ((rd_bank_sel == 1'b0 && bank_full_ping) ||
                    (rd_bank_sel == 1'b1 && bank_full_pong)) begin

                    reading      <= 1'b1;
                    rd_range_idx <= {RANGE_W{1'b0}};
                    rd_pulse_idx <= {PULSE_W{1'b0}};
                end
            end

            // -------------------------------------------------------------
            // issue next RAM read when:
            //   - scheduler active
            //   - no pending RAM return
            //   - output register free
            // -------------------------------------------------------------
            if (reading && !rd_data_valid_r && !out_valid_o) begin
                rd_en_r   <= 1'b1;
                rd_addr_r <= rd_addr_calc;

                rd_range_idx_d1 <= rd_range_idx;
                rd_pulse_idx_d1 <= rd_pulse_idx;
                rd_last_d1      <= (rd_pulse_idx == PULSE_NUM-1);
                rd_bank_last_d1 <= cur_is_last_bank;
                rd_ch_id_d1     <= (rd_bank_sel == 1'b0) ? bank_ch_id_ping : bank_ch_id_pong;

                rd_data_valid_r <= 1'b1;

                // advance logical read index for next issue
                if (cur_is_last_pulse) begin
                    rd_pulse_idx <= {PULSE_W{1'b0}};
                    if (!cur_is_last_range)
                        rd_range_idx <= rd_range_idx + 1'b1;
                end
                else begin
                    rd_pulse_idx <= rd_pulse_idx + 1'b1;
                end
            end
        end
    end

endmodule