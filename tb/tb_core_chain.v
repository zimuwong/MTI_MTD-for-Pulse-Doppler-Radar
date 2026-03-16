//***************************************
//
//        Filename: tb_core_chain.v
//        Author: Koala
//        Description:
//        Create: 2026-3-11
//        Last Modified: 2026-3-16
//
//***************************************

`timescale 1ns/1ps

module tb_core_chain;

localparam N_MAX = 128;

localparam MTI_BYPASS = 2'b00;
localparam MTI_2PULSE = 2'b01;
localparam MTI_3PULSE = 2'b10;

localparam WIN_RECT   = 2'b00;
localparam WIN_HANN   = 2'b01;

// -----------------------------------------------------------------------------
// DUT I/O
// -----------------------------------------------------------------------------
reg                 sys_clk;
reg                 sys_rst_n;

reg     [1:0]       mti_mode_i;
reg     [8:0]       fft_len_i;
reg     [1:0]       win_type_i;
reg                 fft_fwd_inv_i;
reg     [7:0]       fft_scale_sch_i;

reg                 in_valid_i;
wire                in_ready_o;
reg                 in_last_i;
reg     [31:0]      in_data_i;
reg     [12:0]      in_range_idx_i;
reg     [8:0]       in_pulse_idx_i;
reg     [1:0]       in_ch_id_i;

wire                out_valid_o;
reg                 out_ready_i;
wire                out_last_o;
wire    [31:0]      out_data_o;
wire    [12:0]      out_range_idx_o;
wire    [8:0]       out_dopp_idx_o;
wire    [1:0]       out_ch_id_o;

// -----------------------------------------------------------------------------
// stimulus memory
// -----------------------------------------------------------------------------
reg [31:0] stim_mem [0:N_MAX-1];

integer i;
integer fout;
integer fd;

// -----------------------------------------------------------------------------
// DUT
// -----------------------------------------------------------------------------
core_chain_top dut (
    .sys_clk            (sys_clk),
    .sys_rst_n          (sys_rst_n),

    .mti_mode_i         (mti_mode_i),
    .fft_len_i          (fft_len_i),
    .win_type_i         (win_type_i),
    .fft_fwd_inv_i      (fft_fwd_inv_i),
    .fft_scale_sch_i    (fft_scale_sch_i),

    .in_valid_i         (in_valid_i),
    .in_ready_o         (in_ready_o),
    .in_last_i          (in_last_i),
    .in_data_i          (in_data_i),
    .in_range_idx_i     (in_range_idx_i),
    .in_pulse_idx_i     (in_pulse_idx_i),
    .in_ch_id_i         (in_ch_id_i),

    .out_valid_o        (out_valid_o),
    .out_ready_i        (out_ready_i),
    .out_last_o         (out_last_o),
    .out_data_o         (out_data_o),
    .out_range_idx_o    (out_range_idx_o),
    .out_dopp_idx_o     (out_dopp_idx_o),
    .out_ch_id_o        (out_ch_id_o)
);

// -----------------------------------------------------------------------------
// clock
// -----------------------------------------------------------------------------
initial begin
    sys_clk = 1'b0;
    forever #5 sys_clk = ~sys_clk;
end

// -----------------------------------------------------------------------------
// capture FFT output
// -----------------------------------------------------------------------------
always @(posedge sys_clk) begin
    if (out_valid_o && out_ready_i) begin
        $display("[%0t] FFT OUT range=%0d dopp=%0d last=%0d ch=%0d data=%08x",
                 $time, out_range_idx_o, out_dopp_idx_o, out_last_o,
                 out_ch_id_o, out_data_o);

        if (fout != 0)
            $fwrite(fout, "%08x\n", out_data_o);
    end
end

// -----------------------------------------------------------------------------
// reset
// -----------------------------------------------------------------------------
task reset_dut;
begin
    sys_rst_n        = 1'b0;
    
    fft_len_i        = 9'd128;
    fft_fwd_inv_i    = 1'b1;
    fft_scale_sch_i  = 8'b10_10_10_10;

    in_valid_i       = 1'b0;
    in_last_i        = 1'b0;
    in_data_i        = 32'd0;
    in_range_idx_i   = 13'd0;
    in_pulse_idx_i   = 9'd0;
    in_ch_id_i       = 2'd0;

    out_ready_i      = 1'b1;

    fout             = 0;

    repeat (10) @(posedge sys_clk);
    sys_rst_n        = 1'b1;
    repeat (10) @(posedge sys_clk);
end
endtask

// -----------------------------------------------------------------------------
// optional file check
// -----------------------------------------------------------------------------
task check_input_file;
begin
    fd = $fopen("case_real_rbin.txt", "r");
    if (fd == 0) begin
        $display("ERROR: case_real_rbin.txt not found");
        $finish;
    end
    else begin
        $display("OK: case_real_rbin.txt found");
        $fclose(fd);
    end
end
endtask

// -----------------------------------------------------------------------------
// clear stimulus memory to avoid X propagation if readmem fails
// -----------------------------------------------------------------------------
task clear_stim_mem;
begin
    for (i = 0; i < N_MAX; i = i + 1)
        stim_mem[i] = 32'd0;
end
endtask

// -----------------------------------------------------------------------------
// send one frame
// memfile : stimulus hex file
// mode    : mti mode
// win     : window type
// len     : fft length
// outfile : captured fft output file
// -----------------------------------------------------------------------------
task send_frame;
    input [1023:0] memfile;
    input [1:0]    mode;
    input [1:0]    win;
    input [8:0]    len;
    input [1023:0] outfile;
begin
    $display("--------------------------------------------------");
    $display("Load stimulus: %0s", memfile);
    $display("MTI=%0d WIN=%0d LEN=%0d OUT=%0s", mode, win, len, outfile);

    clear_stim_mem();
    $readmemh(memfile, stim_mem);

    mti_mode_i      = mode;
    fft_len_i       = len;
    win_type_i      = win;
    fft_fwd_inv_i   = 1'b1;

    if (len == 9'd64)
        fft_scale_sch_i = 8'b10_10_10_00;
    else
        fft_scale_sch_i = 8'b10_10_10_10;

    fout = $fopen(outfile, "w");
    if (fout == 0) begin
        $display("ERROR: cannot open output file %0s", outfile);
        $finish;
    end

    @(posedge sys_clk);

    for (i = 0; i < len; i = i + 1) begin
        while (!in_ready_o) @(posedge sys_clk);

        in_valid_i      <= 1'b1;
        in_data_i       <= stim_mem[i];
        in_range_idx_i  <= 13'd25;
        in_pulse_idx_i  <= i[8:0];
        in_ch_id_i      <= 2'd0;
        in_last_i       <= (i == len-1);

        @(posedge sys_clk);
    end

    in_valid_i      <= 1'b0;
    in_last_i       <= 1'b0;
    in_data_i       <= 32'd0;
    in_range_idx_i  <= 13'd0;
    in_pulse_idx_i  <= 9'd0;
    in_ch_id_i      <= 2'd0;

    // wait this FFT frame done
    wait(out_valid_o == 1'b1);
    wait(out_valid_o && out_ready_i && out_last_o);
    @(posedge sys_clk);
    repeat (10) @(posedge sys_clk);

    $fclose(fout);
    fout = 0;
end
endtask

// -----------------------------------------------------------------------------
// main sequence
// single case: read one range-gate vector and dump FFT output (3-pulse + hann)
// -----------------------------------------------------------------------------
initial begin
    reset_dut();
    check_input_file();

    send_frame("case_real_rbin.txt", MTI_3PULSE, WIN_HANN, 9'd128, "fft_real_3p_hann.txt");

    $display("Single case done.");
    $finish;
end

endmodule