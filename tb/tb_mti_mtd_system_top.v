`timescale 1ns/1ps

module tb_mti_mtd_system_top;

// =============================================================================
// parameters
// =============================================================================
localparam integer DATA_W    = 32;
localparam integer RANGE_NUM = 4;
localparam integer PULSE_NUM = 128;
localparam integer RANGE_W   = 13;
localparam integer PULSE_W   = 9;
localparam integer CH_W      = 2;
localparam integer ADDR_W    = 14;

localparam integer TOTAL_SAMPLES = RANGE_NUM * PULSE_NUM;
localparam integer FRAME_NUM     = 2;
localparam integer EXPECT_TOTAL  = RANGE_NUM * PULSE_NUM * FRAME_NUM;

localparam [1:0] MTI_BYPASS = 2'b00;
localparam [1:0] MTI_2PULSE = 2'b01;
localparam [1:0] MTI_3PULSE = 2'b10;

localparam [1:0] WIN_RECT   = 2'b00;
localparam [1:0] WIN_HANN   = 2'b01;

// =============================================================================
// DUT I/O
// =============================================================================
reg                     sys_clk;
reg                     sys_rst_n;

// config
reg [1:0]               mti_mode_i;
reg                     auto_mti_en_i;
reg [32:0]              clutter_th_low_i;
reg [32:0]              clutter_th_high_i;
reg [8:0]               fft_len_i;
reg [1:0]               win_type_i;
reg                     fft_fwd_inv_i;
reg [7:0]               fft_scale_sch_i;

// front-end input
reg                     in_valid_i;
wire                    in_ready_o;
reg                     in_last_i;
reg  [DATA_W-1:0]       in_data_i;
reg  [RANGE_W-1:0]      in_range_idx_i;
reg  [PULSE_W-1:0]      in_pulse_idx_i;
reg  [CH_W-1:0]         in_ch_id_i;

// final output
wire                    out_valid_o;
reg                     out_ready_i;
wire                    out_last_o;
wire [DATA_W-1:0]       out_data_o;
wire [RANGE_W-1:0]      out_range_idx_o;
wire [PULSE_W-1:0]      out_dopp_idx_o;
wire [CH_W-1:0]         out_ch_id_o;

// =============================================================================
// stimulus memory
// =============================================================================
reg [DATA_W-1:0] stim_mem [0:TOTAL_SAMPLES-1];

// =============================================================================
// bookkeeping
// =============================================================================
integer out_cnt_total;
integer out_cnt_in_frame;
integer out_cnt_per_range;
integer curr_range_seen;
integer first_output_seen;
integer frame_idx_seen;
integer done_flag;

integer fout_out;
integer fout_mode;
integer fout_clutter;

integer next_out_cnt_total;
integer next_out_cnt_in_frame;
integer next_out_cnt_per_range;
// =============================================================================
// helper
// =============================================================================
function is_x32;
    input [31:0] v;
    begin
        is_x32 = (^v === 1'bx);
    end
endfunction

// =============================================================================
// DUT
// =============================================================================
mti_mtd_system_top #(
    .DATA_W    (DATA_W),
    .RANGE_NUM (RANGE_NUM),
    .PULSE_NUM (PULSE_NUM),
    .RANGE_W   (RANGE_W),
    .PULSE_W   (PULSE_W),
    .CH_W      (CH_W),
    .ADDR_W    (ADDR_W)
) dut (
    .sys_clk            (sys_clk),
    .sys_rst_n          (sys_rst_n),

    .mti_mode_i         (mti_mode_i),
    .auto_mti_en_i      (auto_mti_en_i),
    .clutter_th_low_i   (clutter_th_low_i),
    .clutter_th_high_i  (clutter_th_high_i),
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

// =============================================================================
// clock
// =============================================================================
initial begin
    sys_clk = 1'b0;
    forever #5 sys_clk = ~sys_clk;
end

// =============================================================================
// task: clear input bus
// =============================================================================
task clear_inputs;
begin
    in_valid_i     = 1'b0;
    in_last_i      = 1'b0;
    in_data_i      = {DATA_W{1'b0}};
    in_range_idx_i = {RANGE_W{1'b0}};
    in_pulse_idx_i = {PULSE_W{1'b0}};
    in_ch_id_i     = {CH_W{1'b0}};
end
endtask

// =============================================================================
// task: send one frame from readmemh-loaded memory
// input order in memory: pulse-major
//   pulse0: range0 range1 range2 range3
//   pulse1: range0 range1 range2 range3
//   ...
// =============================================================================
task send_frame_from_mem;
    input [1023:0] memfile;
    input integer  frame_id;
    integer p, r;
    integer idx;
begin
    $readmemh(memfile, stim_mem);

    $display("======================================================");
    $display("Send frame %0d from file: %0s", frame_id, memfile);
    $display("RANGE_NUM=%0d, PULSE_NUM=%0d", RANGE_NUM, PULSE_NUM);
    $display("======================================================");

    idx = 0;
    for (p = 0; p < PULSE_NUM; p = p + 1) begin
        for (r = 0; r < RANGE_NUM; r = r + 1) begin
            @(posedge sys_clk);
            while (!in_ready_o) @(posedge sys_clk);

            if (is_x32(stim_mem[idx])) begin
                $display("[%0t] ERROR: stim_mem[%0d] has X/Z: %08x", $time, idx, stim_mem[idx]);
                $stop;
            end

            in_valid_i     <= 1'b1;
            in_last_i      <= ((p == PULSE_NUM-1) && (r == RANGE_NUM-1));
            in_range_idx_i <= r[RANGE_W-1:0];
            in_pulse_idx_i <= p[PULSE_W-1:0];
            in_ch_id_i     <= 2'd1;
            in_data_i      <= stim_mem[idx];

            if ((p < 2) || (p >= PULSE_NUM-2)) begin
                $display("[%0t] SYS_IN: frame=%0d pulse=%0d range=%0d data=0x%08h last=%0d",
                         $time, frame_id, p, r, stim_mem[idx],
                         ((p == PULSE_NUM-1) && (r == RANGE_NUM-1)));
            end

            @(posedge sys_clk);
            while (!(in_valid_i && in_ready_o)) @(posedge sys_clk);

            clear_inputs();
            idx = idx + 1;
        end
    end
end
endtask

// =============================================================================
// output monitor
// =============================================================================
always @(posedge sys_clk) begin

    if (sys_rst_n && out_valid_o && out_ready_i) begin
        if (fout_out != 0) begin
            $fwrite(fout_out, "%0d %0d %08x %0d\n",
                    out_range_idx_o, out_dopp_idx_o, out_data_o, out_last_o);
        end

        $display("[%0t] SYS_OUT: total=%0d frame_est=%0d range=%0d dopp=%0d data=0x%08h ch=%0d last=%0d",
                 $time,
                 out_cnt_total,
                 frame_idx_seen,
                 out_range_idx_o,
                 out_dopp_idx_o,
                 out_data_o,
                 out_ch_id_o,
                 out_last_o);

        if (!first_output_seen) begin
            first_output_seen = 1;
            curr_range_seen   = out_range_idx_o;
            out_cnt_per_range = 0;
            out_cnt_in_frame  = 0;
        end
        else if (out_range_idx_o != curr_range_seen) begin
            $display("---- range switch: %0d -> %0d ----", curr_range_seen, out_range_idx_o);

            if (out_cnt_per_range != PULSE_NUM) begin
                $display("WARNING: previous range output count = %0d, expected %0d",
                         out_cnt_per_range, PULSE_NUM);
            end

            curr_range_seen   = out_range_idx_o;
            out_cnt_per_range = 0;
        end

        if (out_dopp_idx_o !== out_cnt_per_range[PULSE_W-1:0]) begin
            $display("WARNING: dopp_idx unexpected. range=%0d got=%0d exp=%0d",
                     out_range_idx_o, out_dopp_idx_o, out_cnt_per_range);
        end

        if (out_ch_id_o !== 2'd1) begin
            $display("WARNING: ch_id mismatch. got=%0d exp=1", out_ch_id_o);
        end

        if ((out_cnt_per_range == PULSE_NUM-1) && (out_last_o !== 1'b1)) begin
            $display("WARNING: out_last not asserted at end of range=%0d", out_range_idx_o);
        end

        if ((out_cnt_per_range != PULSE_NUM-1) && (out_last_o !== 1'b0)) begin
            $display("WARNING: out_last asserted early at range=%0d dopp=%0d",
                     out_range_idx_o, out_dopp_idx_o);
        end

        next_out_cnt_total     = out_cnt_total + 1;
        next_out_cnt_per_range = out_cnt_per_range + 1;
        next_out_cnt_in_frame  = out_cnt_in_frame + 1;

        out_cnt_total     = next_out_cnt_total;
        out_cnt_per_range = next_out_cnt_per_range;
        out_cnt_in_frame  = next_out_cnt_in_frame;

        if (next_out_cnt_in_frame == RANGE_NUM * PULSE_NUM) begin
            frame_idx_seen    = frame_idx_seen + 1;
            out_cnt_in_frame  = 0;
            first_output_seen = 0;
        end

        if (next_out_cnt_total == EXPECT_TOTAL) begin
            done_flag = 1;
        end
    end
end

// =============================================================================
// observe adaptive mode map / clutter writes
// =============================================================================
always @(posedge sys_clk) begin
    if (sys_rst_n) begin
        if (dut.clutter_wr_en) begin
            $display("[%0t] CLUTTER_EST: range=%0d power=%0d",
                     $time, dut.clutter_wr_range_idx, dut.clutter_wr_value);
            if (fout_clutter != 0) begin
                $fwrite(fout_clutter, "%0d %0d\n",
                        dut.clutter_wr_range_idx, dut.clutter_wr_value);
            end
        end

        if (dut.mode_wr_en) begin
            $display("[%0t] MODE_SEL: range=%0d mode=%0d",
                     $time, dut.mode_wr_range_idx, dut.mode_wr_value);
            if (fout_mode != 0) begin
                $fwrite(fout_mode, "%0d %0d\n",
                        dut.mode_wr_range_idx, dut.mode_wr_value);
            end
        end

        if (dut.buf_valid && dut.buf_ready && (dut.buf_pulse_idx == 0)) begin
            $display("[%0t] MODE_READ: range=%0d dyn_mti_mode=%0d",
                     $time, dut.buf_range_idx, dut.dyn_mti_mode);
        end
    end
end

// =============================================================================
// main
// =============================================================================
initial begin
    sys_rst_n         = 1'b0;

    mti_mode_i        = MTI_BYPASS;
    auto_mti_en_i     = 1'b1;
    clutter_th_low_i  = 33'd100000;
    clutter_th_high_i = 33'd1000000;

    fft_len_i         = 9'd128;
    win_type_i        = WIN_RECT;         // 第一轮建议先 RECT，方便看闭环
    fft_fwd_inv_i     = 1'b1;
    fft_scale_sch_i   = 8'b10_10_10_10;

    clear_inputs();
    out_ready_i       = 1'b1;

    out_cnt_total     = 0;
    out_cnt_in_frame  = 0;
    out_cnt_per_range = 0;
    curr_range_seen   = 0;
    first_output_seen = 0;
    frame_idx_seen    = 0;
    done_flag         = 0;

    fout_out     = $fopen("sys_out_2frame_4x128.txt", "w");
    fout_mode    = $fopen("mode_map_updates.txt", "w");
    fout_clutter = $fopen("clutter_updates.txt", "w");

    if (fout_out == 0)     $display("WARNING: cannot open sys_out_2frame_4x128.txt");
    if (fout_mode == 0)    $display("WARNING: cannot open mode_map_updates.txt");
    if (fout_clutter == 0) $display("WARNING: cannot open clutter_updates.txt");

    repeat (10) @(posedge sys_clk);
    sys_rst_n = 1'b1;
    repeat (10) @(posedge sys_clk);

    // frame 0: build clutter/mode map
    send_frame_from_mem("case_real_rbin_4rg.txt", 0);

    // let pipeline drain a bit
    repeat (200) @(posedge sys_clk);

    // frame 1: adaptive mode should take effect
    send_frame_from_mem("case_real_rbin_4rg.txt", 1);

    wait(done_flag == 1);
    repeat (50) @(posedge sys_clk);

    $display("======================================================");
    $display("Simulation finished.");
    $display("Total output count = %0d", out_cnt_total);
    $display("Expected total    = %0d", EXPECT_TOTAL);
    $display("======================================================");

    if (fout_out != 0)     $fclose(fout_out);
    if (fout_mode != 0)    $fclose(fout_mode);
    if (fout_clutter != 0) $fclose(fout_clutter);

    $finish;
end

// =============================================================================
// timeout protection
// =============================================================================
initial begin
    #5000000;
    $display("[%0t] ERROR: simulation timeout", $time);
    $finish;
end

endmodule