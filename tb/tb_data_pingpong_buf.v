`timescale 1ns/1ps

module tb_data_pingpong_buf;

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

// =============================================================================
// DUT I/O
// =============================================================================
reg                     sys_clk;
reg                     sys_rst_n;

// input stream
reg                     in_valid_i;
wire                    in_ready_o;
reg                     in_last_i;
reg  [DATA_W-1:0]       in_data_i;
reg  [RANGE_W-1:0]      in_range_idx_i;
reg  [PULSE_W-1:0]      in_pulse_idx_i;
reg  [CH_W-1:0]         in_ch_id_i;

// output stream
wire                    out_valid_o;
reg                     out_ready_i;
wire                    out_last_o;
wire [DATA_W-1:0]       out_data_o;
wire [RANGE_W-1:0]      out_range_idx_o;
wire [PULSE_W-1:0]      out_pulse_idx_o;
wire [CH_W-1:0]         out_ch_id_o;

// =============================================================================
// stimulus memory
// =============================================================================
reg [DATA_W-1:0] stim_mem [0:TOTAL_SAMPLES-1];

// =============================================================================
// bookkeeping
// =============================================================================
integer out_cnt_total;
integer out_cnt_per_range;
integer curr_range_seen;
integer first_output_seen;
integer done_flag;
integer exp_idx;

integer next_out_cnt_total;
integer next_out_cnt_per_range;

integer fout_out;

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
data_pingpong_buf #(
    .DATA_W    (DATA_W),
    .RANGE_NUM (RANGE_NUM),
    .PULSE_NUM (PULSE_NUM),
    .RANGE_W   (RANGE_W),
    .PULSE_W   (PULSE_W),
    .CH_W      (CH_W),
    .ADDR_W    (ADDR_W)
) dut (
    .sys_clk         (sys_clk),
    .sys_rst_n       (sys_rst_n),

    .in_valid_i      (in_valid_i),
    .in_ready_o      (in_ready_o),
    .in_last_i       (in_last_i),
    .in_data_i       (in_data_i),
    .in_range_idx_i  (in_range_idx_i),
    .in_pulse_idx_i  (in_pulse_idx_i),
    .in_ch_id_i      (in_ch_id_i),

    .out_valid_o     (out_valid_o),
    .out_ready_i     (out_ready_i),
    .out_last_o      (out_last_o),
    .out_data_o      (out_data_o),
    .out_range_idx_o (out_range_idx_o),
    .out_pulse_idx_o (out_pulse_idx_o),
    .out_ch_id_o     (out_ch_id_o)
);

// =============================================================================
// clock
// =============================================================================
initial begin
    sys_clk = 1'b0;
    forever #5 sys_clk = ~sys_clk;
end

// =============================================================================
// clear inputs
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
// init stimulus memory
// pulse-major:
//   pulse0: range0 range1 range2 range3
//   pulse1: range0 range1 range2 range3
//   ...
// data format just uses an easy-to-check pattern:
//   data = {8'hA5, pulse_idx[7:0], range_idx[7:0], 8'h3C}
// =============================================================================
task build_stimulus;
    integer p, r;
    integer idx;
begin
    idx = 0;
    for (p = 0; p < PULSE_NUM; p = p + 1) begin
        for (r = 0; r < RANGE_NUM; r = r + 1) begin
            stim_mem[idx] = {8'hA5, p[7:0], r[7:0], 8'h3C};
            idx = idx + 1;
        end
    end
end
endtask

// =============================================================================
// send one frame
// =============================================================================
task send_one_frame;
    integer p, r;
    integer idx;
begin
    idx = 0;

    $display("======================================================");
    $display("Send 1 frame to data_pingpong_buf");
    $display("RANGE_NUM=%0d, PULSE_NUM=%0d", RANGE_NUM, PULSE_NUM);
    $display("======================================================");

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
            in_data_i      <= stim_mem[idx];
            in_range_idx_i <= r[RANGE_W-1:0];
            in_pulse_idx_i <= p[PULSE_W-1:0];
            in_ch_id_i     <= 2'd1;

            if ((p < 2) || (p >= PULSE_NUM-2)) begin
                $display("[%0t] BUF_IN: pulse=%0d range=%0d data=0x%08h last=%0d",
                         $time, p, r, stim_mem[idx],
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
// expected output order: range-major
//   range0: pulse0..127
//   range1: pulse0..127
//   ...
// =============================================================================
always @(posedge sys_clk) begin
    if (sys_rst_n && out_valid_o && out_ready_i) begin
        if (fout_out != 0) begin
            $fwrite(fout_out, "%0d %0d %08x %0d\n",
                    out_range_idx_o, out_pulse_idx_o, out_data_o, out_last_o);
        end

        $display("[%0t] BUF_OUT: total=%0d range=%0d pulse=%0d data=0x%08h ch=%0d last=%0d",
                 $time,
                 out_cnt_total,
                 out_range_idx_o,
                 out_pulse_idx_o,
                 out_data_o,
                 out_ch_id_o,
                 out_last_o);

        if (!first_output_seen) begin
            first_output_seen = 1;
            curr_range_seen   = out_range_idx_o;
            out_cnt_per_range = 0;
        end
        else if (out_range_idx_o != curr_range_seen) begin
            $display("---- range switch: %0d -> %0d ----", curr_range_seen, out_range_idx_o);

            if (out_cnt_per_range != PULSE_NUM) begin
                $display("ERROR: previous range output count = %0d, expected %0d",
                         out_cnt_per_range, PULSE_NUM);
                $stop;
            end

            curr_range_seen   = out_range_idx_o;
            out_cnt_per_range = 0;
        end

        if (out_pulse_idx_o !== out_cnt_per_range[PULSE_W-1:0]) begin
            $display("ERROR: pulse order mismatch. range=%0d got=%0d exp=%0d",
                     out_range_idx_o, out_pulse_idx_o, out_cnt_per_range);
            $stop;
        end

        if (out_ch_id_o !== 2'd1) begin
            $display("ERROR: ch_id mismatch. got=%0d exp=1", out_ch_id_o);
            $stop;
        end

        exp_idx = out_pulse_idx_o * RANGE_NUM + out_range_idx_o;
        if (out_data_o !== stim_mem[exp_idx]) begin
            $display("ERROR: data mismatch. idx=%0d range=%0d pulse=%0d got=0x%08h exp=0x%08h",
                     exp_idx, out_range_idx_o, out_pulse_idx_o, out_data_o, stim_mem[exp_idx]);
            $stop;
        end

        if ((out_cnt_per_range == PULSE_NUM-1) && (out_last_o !== 1'b1)) begin
            $display("ERROR: out_last not asserted at end of range=%0d", out_range_idx_o);
            $stop;
        end

        if ((out_cnt_per_range != PULSE_NUM-1) && (out_last_o !== 1'b0)) begin
            $display("ERROR: out_last asserted early at range=%0d pulse=%0d",
                     out_range_idx_o, out_pulse_idx_o);
            $stop;
        end

        next_out_cnt_total     = out_cnt_total + 1;
        next_out_cnt_per_range = out_cnt_per_range + 1;

        out_cnt_total     = next_out_cnt_total;
        out_cnt_per_range = next_out_cnt_per_range;

        if (next_out_cnt_total == TOTAL_SAMPLES) begin
            done_flag = 1;
        end
    end
end

// =============================================================================
// debug prints for internal state
// =============================================================================
always @(posedge sys_clk) begin
    if (sys_rst_n && in_valid_i && in_ready_o) begin
        if (in_last_i) begin
            $display("[%0t] BUF_LAST_IN accepted", $time);
        end
    end
end

always @(posedge sys_clk) begin
    if (sys_rst_n && dut.bank_full_ping)
        $display("[%0t] DBG: bank_full_ping=1", $time);
    if (sys_rst_n && dut.bank_full_pong)
        $display("[%0t] DBG: bank_full_pong=1", $time);
end

// =============================================================================
// main
// =============================================================================
initial begin
    sys_rst_n         = 1'b0;
    out_ready_i       = 1'b1;

    clear_inputs();
    build_stimulus();

    out_cnt_total      = 0;
    out_cnt_per_range  = 0;
    curr_range_seen    = 0;
    first_output_seen  = 0;
    done_flag          = 0;

    next_out_cnt_total     = 0;
    next_out_cnt_per_range = 0;

    fout_out = $fopen("buf_out_4x128.txt", "w");
    if (fout_out == 0)
        $display("WARNING: cannot open buf_out_4x128.txt");

    repeat (10) @(posedge sys_clk);
    sys_rst_n = 1'b1;
    repeat (10) @(posedge sys_clk);

    send_one_frame();

    wait(done_flag == 1);
    repeat (20) @(posedge sys_clk);

    $display("======================================================");
    $display("data_pingpong_buf simulation finished.");
    $display("Total output count = %0d", out_cnt_total);
    $display("Expected total    = %0d", TOTAL_SAMPLES);
    $display("======================================================");

    if (fout_out != 0)
        $fclose(fout_out);

    $finish;
end

// =============================================================================
// timeout protection
// =============================================================================
initial begin
    #30000000;
    $display("[%0t] ERROR: simulation timeout", $time);
    $finish;
end

endmodule
