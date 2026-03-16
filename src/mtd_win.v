//***************************************
//
//        Filename: mtd_win.v
//        Author: Koala
//        Description:
//        Create: 2026-3-11
//        Last Modified: 2026-3-16
//
//***************************************
module mtd_win (
    input               sys_clk,
    input               sys_rst_n,

    // window config
    input       [8:0]   fft_len_i,       // 64/128/256...
    input       [1:0]   win_type_i,      // 2'b00:RECT 2'b01:HANN

    // input stream
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

localparam WIN_RECT = 2'b00;
localparam WIN_HANN = 2'b01;

// Hann window ROMs (Q15)
reg signed [15:0] hann64_rom  [0:63];
reg signed [15:0] hann128_rom [0:127];
reg signed [15:0] hann256_rom [0:255];
integer rom_i;

initial begin
    // Default to unity in case file load fails.
    for (rom_i = 0; rom_i < 64; rom_i = rom_i + 1)
        hann64_rom[rom_i] = 16'sd32767;
    for (rom_i = 0; rom_i < 128; rom_i = rom_i + 1)
        hann128_rom[rom_i] = 16'sd32767;
    for (rom_i = 0; rom_i < 256; rom_i = rom_i + 1)
        hann256_rom[rom_i] = 16'sd32767;

    $readmemh("hann_64_q15.hex", hann64_rom);
    $readmemh("hann_128_q15.hex", hann128_rom);
    $readmemh("hann_256_q15.hex", hann256_rom);
end

// -----------------------------------------------------------------------------
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

assign out_fire   = out_valid_r & out_ready_i;
assign in_ready_o = (~out_valid_r) | out_ready_i;
assign in_fire    = in_valid_i & in_ready_o;

// -----------------------------------------------------------------------------
// input unpack
// -----------------------------------------------------------------------------
wire signed [15:0] din_i;
wire signed [15:0] din_q;

assign din_i = in_data_i[15:0];
assign din_q = in_data_i[31:16];

// -----------------------------------------------------------------------------
// window coefficient (Q15)
// RECT : 32767
// HANN : lookup by pulse index
// -----------------------------------------------------------------------------
wire signed [15:0] hann64_coef  = (in_pulse_idx_i < 9'd64)  ? hann64_rom[in_pulse_idx_i[5:0]]   : 16'sd0;
wire signed [15:0] hann128_coef = (in_pulse_idx_i < 9'd128) ? hann128_rom[in_pulse_idx_i[6:0]]  : 16'sd0;
wire signed [15:0] hann256_coef = (in_pulse_idx_i < 9'd256) ? hann256_rom[in_pulse_idx_i[7:0]]  : 16'sd0;

wire signed [15:0] win_coef_q15 =
    (win_type_i == WIN_RECT) ? 16'sd32767 :
    (win_type_i == WIN_HANN) ?
        ((fft_len_i == 9'd64)  ? hann64_coef  :
         (fft_len_i == 9'd128) ? hann128_coef :
         (fft_len_i == 9'd256) ? hann256_coef :
                                 hann128_coef) :
    16'sd32767;

// -----------------------------------------------------------------------------
// multiply: data * win_coef_q15
// 16bit x 16bit -> 32bit
// then >>> 15 to restore amplitude
// -----------------------------------------------------------------------------
wire signed [31:0] mult_i = din_i * win_coef_q15;
wire signed [31:0] mult_q = din_q * win_coef_q15;

wire signed [31:0] round_i = (mult_i >= 0) ? (mult_i + 32'sd16384) : (mult_i - 32'sd16384);
wire signed [31:0] round_q = (mult_q >= 0) ? (mult_q + 32'sd16384) : (mult_q - 32'sd16384);

wire signed [16:0] scaled_i = round_i >>> 15;
wire signed [16:0] scaled_q = round_q >>> 15;

wire signed [15:0] dout_i =
    (scaled_i > 17'sd32767) ? 16'sh7fff :
    (scaled_i < -17'sd32768) ? 16'sh8000 :
    scaled_i[15:0];

wire signed [15:0] dout_q =
    (scaled_q > 17'sd32767) ? 16'sh7fff :
    (scaled_q < -17'sd32768) ? 16'sh8000 :
    scaled_q[15:0];

// -----------------------------------------------------------------------------
// output register
// -----------------------------------------------------------------------------
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        out_valid_r      <= 1'b0;
        out_last_r       <= 1'b0;
        out_data_r       <= 32'd0;
        out_range_idx_r  <= 13'd0;
        out_pulse_idx_r  <= 9'd0;
        out_ch_id_r      <= 2'd0;
    end
    else begin
        if (out_fire)
            out_valid_r <= 1'b0;

        if (in_fire) begin
            out_valid_r      <= 1'b1;
            out_last_r       <= in_last_i;
            out_data_r       <= {dout_q, dout_i};
            out_range_idx_r  <= in_range_idx_i;
            out_pulse_idx_r  <= in_pulse_idx_i;
            out_ch_id_r      <= in_ch_id_i;
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