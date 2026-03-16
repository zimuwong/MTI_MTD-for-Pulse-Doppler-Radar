# MTI_MTD计算核设计

## 项目概述

本设计实现了一条MTI + MTD的计算核，用于对单距离门的慢时间复数序列进行动目标检测的处理。

系统的处理对象为脉冲压缩之后、距离门上的慢时间复数数据。整体处理流程为：

输入慢时间复数序列→MTI 对消→多普勒加窗→慢时间 FFT→结果输出打包

计算核心由以下 5 个核心模块组成：

- `core_chain_top.v`

- `mti_core.v`

- `mtd_win.v`

- `fft_ip_wrap.v`

- `out_pack.v`

---

## 系统结构与模块功能

### 顶层模块 `core_chain_top`

`core_chain_top` 是整条处理链的系统顶层，负责把各级处理模块按顺序连接起来。其内部数据路径为：in_data_i→ mti_core→ mtd_win→ fft_ip_wrap→ out_pack→ out_data_o

顶层接口包含三部分：系统时钟与复位、运行配置接口、输入输出流接口。该模块完成了完整的慢时间处理流水连接，便于后续继续扩展距离维处理、检测逻辑或多通道处理。

---

### MTI 模块 `mti_core`

`mti_core` 对输入慢时间复数序列进行 MTI 对消，支持三种工作模式：

- `2'b00`：bypass

- `2'b01`：2-pulse MTI

- `2'b10`：3-pulse MTI

模块将输入 `in_data_i` 按 `{Q[15:0], I[15:0]}` 解包为实部和虚部，分别做有符号运算。内部使用延时寄存器 `dly1`、`dly2` 保存前一拍和前两拍样本，用于构造 2 脉冲和 3 脉冲对消器。

对于边界点，代码采用如下规则：

- 2-pulse 时 `pulse_idx=0` 输出 0

- 3-pulse 时 `pulse_idx=0/1` 输出 0

运算结果经过饱和截断后重新打包成 32 位复数输出。

---

### 窗函数模块 `mtd_win`

`mtd_win` 用于对 MTI 输出进行慢时间窗加权，支持两种窗类型：

- `WIN_RECT`：矩形窗

- `WIN_HANN`：Hann 窗

当前实现中：

- Rect 窗直接使用系数 32767（Q15 近似 1）

- Hann 窗通过 ROM 查表实现

---

### FFT 封装模块 `fft_ip_wrap`

`fft_ip_wrap` 对接 Vivado FFT IP 核，完成慢时间 FFT 运算。

该模块的作用主要包括：

- 根据 `fft_len_i` 生成 FFT 配置字

- 在输入一帧数据前先发送 FFT config

- 按 AXI-Stream 格式将窗后数据送入 FFT IP

- 接收 FFT 输出

- 为每个 FFT 输出样点补充 `range_idx`、`dopp_idx`、`ch_id`

`fft_scale_sch_i` 用于配置运行时缩放策略，`fft_fwd_inv_i` 用于设置正反变换方向。当前采用正向 FFT。

模块内部使用状态机控制整个 FFT 帧处理流程：

- `ST_IDLE`

- `ST_SEND_CFG`

- `ST_SEND_DATA`

- `ST_RECV_DATA`

该模块不仅完成 FFT 数据计算，也起到配置、输入和输出时序管理的作用。后续为支持可变点FFT，需要增加配置字逻辑并更改IP核配置。

---

### 输出打包模块 `out_pack`

主要作用是：对输出流进行一级寄存、保持接口整齐、便于后续模块级扩展。

---

## 数据接口说明

### 系统配置接口

顶层配置接口包括：

- `mti_mode_i [1:0]`：MTI 模式选择

- `fft_len_i [8:0]`：FFT 点数

- `win_type_i [1:0]`：窗类型选择

- `fft_scale_sch_i [7:0]`：FFT 缩放调度

### 输入数据接口

顶层输入接口包括：

- `in_valid_i`：输入有效

- `in_ready_o`：模块可接收数据

- `in_last_i`：当前帧最后一个样点

- `in_data_i [31:0]`：输入复数数据

- `in_range_idx_i [12:0]`：距离门索引

- `in_pulse_idx_i [8:0]`：脉冲序号

- `in_ch_id_i [1:0]`：通道编号

其中 `in_data_i` 的格式为：`{Q[15:0], I[15:0]}`

### 输出数据接口

顶层输出接口包括：

- `out_valid_o`

- `out_ready_i`

- `out_last_o`

- `out_data_o [31:0]`

- `out_range_idx_o [12:0]`

- `out_dopp_idx_o [8:0]`

- `out_ch_id_o [1:0]`

其中输出为：某距离门、某通道上的多普勒谱第 k 个 bin 的复数结果

- `out_data_o` 为 FFT 输出复数数据，格式仍为 `{Q[15:0], I[15:0]}`

- `out_dopp_idx_o` 为 FFT 输出 bin 编号

- `out_range_idx_o` 与 `out_ch_id_o` 保留当前帧所属的距离门和通道信息

---

## MATLAB 对比结果

3-pulse MTI加Hann窗，使用matlab仿真脉冲雷达数据

生成误差图：

实部：

![mtimtd核实部对比.png](D:\科研\数字IC\note\images\edb4e090d62edc9a80b867a9f786373e352f6fe5.png)

虚部：

![mtimtd核虚部对比.png](D:\科研\数字IC\note\images\3cd77cb3735d1e070e25120df351241776e38570.png)

当前 MTI +MTD整条链路能够正确完成计算，且 Verilog 与 MATLAB 参考结果具有较高一致性。


