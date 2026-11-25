# 复现指南（REPRODUCE）

> 目标：**拿到一块空白 RK3588 板子的人，照着这份文档能把本仓库跑到「能对话」为止。**
>
> 每一步都写了「期望看到什么」。看不到就是这一步没成，别往下走 ——
> 这个项目里最难查的 bug 全是「上一步静默失败了，下一步看起来正常」。

---

## 0. 三条复现路径，按难度排序

| 路径 | 需要什么 | 能跑出什么 | 建议 |
| :--- | :--- | :--- | :--- |
| **① 纯文本 Agent**（推荐先走这条） | 模型 + runtime | 打字问「板子多热」，模型自己调工具读温度 | ✅ 起点，门槛最低 |
| **② 视觉推流** | + 摄像头 + opencv4 | 9000 端口推 248B 检测帧，浏览器看 8080 预览 | 板子有 UVC 摄像头再走 |
| **③ 语音交互** | + 麦克风 + 扬声器 + ASR/TTS 模型 | 说「小瑞，温度多少」，它答出来 | 最难，最后再弄 |

**②③ 不通不影响 ①。** ① 是项目核心（大模型 + 硬件 Tool Calling），
②③ 是外面包的皮。

---

## 1. 硬件与系统前提

实测环境（本项目的全部数字都来自这套配置）：

| 项 | 值 |
| :--- | :--- |
| 板子 | EVM3588-B（英码科技 EMA），RK3588 / 8 GB LPDDR4x / 64 GB eMMC |
| 系统 | Debian 11 (bullseye)，内核 **5.10.110** |
| NPU 驱动 | 版本需 ≥ 0.9.2（`cat /sys/kernel/debug/rknpu/version` 可查） |
| 编译器 | 板端 `g++`（Debian 11 自带 10.2.1） |

**必须板端原生编译，不要交叉编译。** PC 端 Ubuntu 22 的 glibc 2.35 编出来的二进制，
在板子 Debian 11 的 glibc 2.31 上跑不起来 —— 这是本项目反复撞的第一堵墙。

```bash
# 板端自检，确认硬件基本盘
bash tools/01_probe.sh 2>/dev/null || bash build/../../tools/01_probe.sh 2>/dev/null || true
uname -m                    # 期望 aarch64
nproc                       # 期望 8
free -g                     # 期望 total ≥ 7
ls /sys/class/leds/         # 期望看到 work（见下面「LED 节点」一节）
```

### 硬件差异须知

本项目的**四个口子写死在这块板子上**，换板子要改。都已经做成可配置：

| 东西 | 本机值 | 怎么改 |
| :--- | :--- | :--- |
| 工作指示灯 | `/sys/class/leds/work/` | 改 `agent/*.cpp` 里的 `LED_*` 常量。**别人的板子上大概率没有 `work` 这个名字** |
| 摄像头 | `/dev/video81`、`/dev/video83` | `Environment=` 或命令行参数，见各 service 文件 |
| 麦克风 | `hw:0,0`（摄像头自带） | 环境变量 `VGW_MIC_DEV` |
| 扬声器 | `hw:2,0`（ES8388 耳机口） | 环境变量 `VGW_SPK_DEV` |

查设备号：

```bash
arecord -l     # 采集设备 → 填 VGW_MIC_DEV
aplay -l       # 播放设备 → 填 VGW_SPK_DEV
v4l2-ctl --list-devices
```

---

## 2. 三个必须自己准备的东西（**不在仓库里**）

这是复现唯一真正的门槛。三个都不进仓库，原因：2.98 GB 体积 + 厂商许可。

### 2.1 RKLLM runtime（`librkllmrt.so` + `rkllm.h`，约 7 MB）

来自 **Rockchip RKLLM SDK**。项目实测可用版本：**rkllm-runtime v1.3.1**。

```bash
# 拿到后放到这个目录，与 Agent 二进制同级
mkdir -p /root/rkllm_deploy
cp rkllm.h librkllmrt.so /root/rkllm_deploy/
```

> 为什么必须放在同一目录：Agent 编译用 `-L. -lrkllmrt -Wl,-rpath,'$ORIGIN'`，
> 运行时按相对路径找库。**模型也用相对路径加载**，所以必须 `cd /root/rkllm_deploy` 再运行。

### 2.2 大模型（`qwen3.5-2b_w8a8_rk3588.rkllm`，约 2.98 GB）

**这一步仓库里没有转换脚本，是本项目的一个已知缺口。**

模型来自 Qwen3.5-2B 的 W8A8 量化 + RKLLM 格式转换。官方转换链路：

```bash
# 在 PC（Linux / WSL2，Python 3.10）上做，不在板子上做
pip install rkllm-toolkit

python3 -c "
from rkllm.api import RKLLM
m = RKLLM('./Qwen3.5-2B', 'qwen3.5-2b_w8a8_rk3588.rkllm',
          target_platform='rk3588', quantized_dtype='w8a8')
m.load_huggingface_model()
m.build(do_quantization=True, dataset='./calib_data.json')
"
```

> ⚠️ **上述命令是通用写法，不是本项目的实测脚本。** 本项目当时是在板子上用
> rknn-toolkit2 的 aarch64 wheel 直跑的视觉模型；**大模型的转换记录没有留下来**。
> 如果你照上面跑不通，这是本仓库已知的复现断点，不是你的问题。

检查模型是否就位：

```bash
ls -lh /root/rkllm_deploy/*.rkllm       # 期望约 2.98G
```

### 2.3 语音模型（只在走路径 ③ 时需要）

| 模型 | 期望路径 | 来源 |
| :--- | :--- | :--- |
| sherpa-onnx 静态包（v1.12.12 aarch64） | `/root/asr/sherpa-onnx-v1.12.12-linux-aarch64-static/` | sherpa-onnx GitHub Releases |
| Paraformer 中文 ASR | `/root/asr/sherpa-onnx-paraformer-zh-small-2024-03-09/` | sherpa-onnx 模型库 |
| Silero VAD | `/root/asr/silero_vad.onnx` | 同上 |
| VITS TTS（fanchen） | `/root/asr/tts-fanchen/` | 同上 |

**没有这些也能跑路径 ①** —— 语音网关会自动降级成纯文本模式，不会崩。

---

## 3. 视觉模型（路径 ② 需要）

```bash
# 转 YOLOv8n 为 RK3588 INT8（PC 侧，需 rknn-toolkit2 1.6.0）
bash build/../tools/rknn_convert_v2.py   # 见脚本内 --help

# 产物放到：
/root/edgevision/data/models/yolov8n_dflfree_rk3588_i8.rknn
```

> 注意 `vision/*.cpp` 里 `MODEL_PATH` 是**写死的绝对路径**，改模型位置要改源码。

---

## 4. 板端目录结构

板上目录和仓库结构**不同**，这是刻意的（对齐 systemd unit 的 `ExecStart`）：

```bash
mkdir -p /root/rkllm_deploy /root/lab /root/patrol /root/asr \
         /root/edgevision/data/models
```

| 板上路径 | 放什么 | 从仓库哪里来 |
| :--- | :--- | :--- |
| `/root/rkllm_deploy/` | Agent 二进制 + 模型 + rkllm.h + librkllmrt.so | `build/build_embodied_agent.sh` |
| `/root/lab/` | 网关/预览/守护二进制 | `build/build_*.sh` 加 `OUT=/root/lab` |
| `/root/voice_gateway` | 语音网关二进制 | `build/build_voice_gateway.sh` + `OUT=/root` |
| `/root/tts_daemon` | TTS 常驻守护 | `build/build_tts_daemon.sh` + `OUT=/root` |
| `/root/patrol/` | 巡检事件日志（运行时自动建） | — |
| `/root/asr/` | ASR/TTS 模型 | 自己准备（见 2.3） |

---

## 5. 编译（按依赖从少到多）

> **没有板子、或者板子暂时不在手边？** 先跑 `bash build/check_syntax.sh`。
> 它用 `build/check_stubs/` 里的桩头文件，在**任何 PC 上**检查全部 5 个主程序的
> 语法与类型，不需要板子、不需要 SDK、不需要 opencv。能抓「改了字段名没改全」
> 「API 名字写错」这类错。**但它不能证明板端能跑** —— 桩头文件没有真实现。

```bash
cd <仓库根>

# ⓪ 无板子可用的编译检查
bash build/check_syntax.sh

# ① 零外部依赖，先编这三个确认工具链正常
bash build/build_agent_server.sh        # → edgevision_agent_server（8088 控制面）
bash build/build_patrol_daemon.sh       # → edgevision_patrol_daemon（巡检守护）
bash build/build_voice_gateway.sh       # → voice_gateway（语音编排）

# ② 需要 RKLLM SDK（2.1）
DEPLOY=/root/rkllm_deploy bash build/build_embodied_agent.sh

# ③ 需要 opencv4 + rknnrt（本仓库已带 librknnrt.so）
OUT=/root/lab bash build/build_w4_gateway.sh    # 9000 网关
OUT=/root/lab bash build/build_preview.sh      # 8080 预览

# ④ 需要 sherpa-onnx 静态包（2.3）
OUT=/root SHERPA_ROOT=/root/asr/sherpa-onnx-v1.12.12-linux-aarch64-static \
  bash build/build_tts_daemon.sh
```

**系统包**（路径 ② 需要）：

```bash
apt-get install -y libopencv-dev pkg-config
```

---

## 6. 验证：每步该看到什么

### 6.1 纯文本 Agent（路径 ①，最重要的一个验证）

```bash
cd /root/rkllm_deploy
./rkllm_embodied_agent
```

期望看到：

```
========================================================
🚀 RK3588 纯端侧原生具身智能体 (On-Device Embodied Agent)
   - 大脑底座: Qwen3.5-2B (W8A8 高精度量化, 3核物理 NPU)
   - 神经手脚: Linux sysfs / DRM / POSIX Socket 原生闭环
========================================================
[Init] 加载端侧大模型并绑定 NPU 3核与 A76 大核...
✓ ...（预热约 30 s）
EdgeAgent>
```

然后输入：`现在板子温度多少`

期望：模型**自己**输出 `<tool_call>` 调 `get_system_health`，
读到真实温度后再总结成一句话。**看到真实温度数字 = 路径 ① 成功。**

> 首次 prefill 约 28~30 s（2000+ 字 system prompt），之后 KV cache 命中约 9~10 s。
> 如果一直停在 `[Init]` 不动 → 大概率是 `rkllm_init failed`，看
> 「常见失败」第 1 条。

### 6.2 无麦克风跑语音网关（强烈推荐先测这个）

```bash
/root/voice_gateway --ask "现在板子温度多少"
```

这一条**不需要任何声卡**，它不启动 ASR 子进程，只调 Agent 并把文字打出来。

或者交互式：

```bash
/root/voice_gateway --no-asr
# 输入问题 → 回车 → 看回答 → Ctrl+D 退出
```

期望日志：

```
════ 纯文本模式（无麦克风）════
输入问题后回车；Ctrl+D 退出。语音输入/播报已禁用。
✓ Agent 子进程就绪 pid=xxx
✓ 预热完成，耗时 30s
```

### 6.3 视觉（路径 ②）

```bash
systemctl start edgevision                     # 9000 网关
tail -f /var/log/syslog | grep NPU             # 期望看到 [NPU Core #0] 16~22 ms | 检出 N 目标
```

**必须验证这两条，否则你编出来的是假推理：**

```bash
strings /root/lab/w4_edgevision_gateway | grep -c "x86 Stub Mode"   # 必须 0
nm -C /root/lab/w4_edgevision_gateway | grep -c cam_read            # 必须 ≥ 1
```

> 这条坑本项目踩过：漏了 `-DENABLE_RKNN` 时**编译零告警、启动成功、帧号一路涨**，
> 但日志有 `[!] x86 Stub Mode (no NPU)`、NPU 耗时恒 0 ms、结果恒「检出 0 目标」。
> 画面和端口全都正常，只有结果是假的。现在 `build_w4_gateway.sh` 里已加自动断言。

### 6.4 语音（路径 ③）

```bash
bash tests/loop_check.sh      # 先验声学回路！不过就别往下测
bash tests/test_e2e.sh        # 端到端：板子说给自己听
```

> **`loop_check.sh` 不过的时候，`test_e2e.sh` 依然会产出「0/10 + 幻觉文本」，
> 那不是识别率差，是没有测量。** 这是本项目踩过最深的坑之一：
> 耳机插着 → 声音进耳机不进空气 → 麦克风只录到底噪 → ASR 对着噪声硬编出
> 「小孩女孩玩的玩具」。所以 `loop_check.sh` 必须作为前置门槛。

---

## 7. 常见失败

| 现象 | 原因 | 怎么修 |
| :--- | :--- | :--- |
| `rkllm_init failed: -1` / `errno 14` | NPU IOMMU（只有 **4 GiB**）地址空间耗尽。每个 rkllm 实例约 1.95 GB | `systemctl stop edgevision` 腾出 NPU；或重启板子复位 |
| `load model file error!` | 没用相对路径 + 不在 `/root/rkllm_deploy` 下运行 | `cd /root/rkllm_deploy` 再跑 |
| `stray '\r'` 编译报错 | 源码是 Windows CRLF | 编译脚本已做 `tr -d '\r'`，手工编时要自己做 |
| 编出 x86 桩（NPU 恒 0 ms） | 漏 `-DENABLE_RKNN` | 见 6.3 |
| 网关/预览起来但端口没监听 | 摄像头被别的进程占 | `fuser -v /dev/video83`，一个 V4L2 设备只能一个进程 |
| 语音网关卡住不响应 | 麦克风被残留 ASR 占 | `fuser -k -9 /dev/snd/pcmC0D0c` |
| `arecord -l` 没有设备 | 真没麦克风 | 用路径 ①，或 `--no-asr` |

---

## 8. 本仓库没有、但你可能想要的东西

诚实列出来，免得你照文档找半天：

| 缺什么 | 影响 | 状态 |
| :--- | :--- | :--- |
| `.rkllm` 模型的**实测转换脚本** | 只能按 2.2 的通式自己试 | 已知缺口 |
| `rkllm.h` / `librkllmrt.so` | 需从 SDK 取 | 许可原因不进仓库 |
| 板端 MPP/RGA SDK 头（`rk_mpi.h` 等） | `tools/` 里 10 个攻坚工具编不了 | 不影响 6 个主程序 |
| `deploy/cpp` 的完整 CMake 工程 | 只有引擎和后处理被抽出来，`edgevision_pro` 等 target 没有 | 本仓库只带运行所需 |
| ESP32 云台固件 | `control_service` 里舵机那条会报「物理缺失」 | 硬件没到货 |

---

## 9. 只有一块板子，怎么验证「别人也能装」

**不需要第二块板子。** 所有脚本的路径都可配（`DEPLOY=` / `OUT=` / `SHERPA_ROOT=`），
所以可以在**同一块板子的另一个目录**里做一次完整冷启动，完全不碰现有部署：

```bash
# 在板子上建一个干净的测试根目录
export T=/root/repro_test
mkdir -p $T

# 把所有东西都往这里装，不碰 /root/rkllm_deploy 和 /root/lab
OUT=$T DEPLOY=$T bash build/bootstrap.sh

# 模型和 runtime 可以软链接过来（不占额外空间）
ln -sf /root/rkllm_deploy/librkllmrt.so $T/
ln -sf /root/rkllm_deploy/rkllm.h      $T/
ln -sf /root/rkllm_deploy/*.rkllm      $T/

# 用测试目录的模型跑一次，证明脚本链路是通的
cd $T && ./rkllm_embodied_agent
```

这就是一次真实的「干净安装」验证。**只有在 `/root/repro_test` 里能跑通，
才说明别人照 REPRODUCE.md 也能跑通。** 现在直接跑 `/root/rkllm_deploy` 的东西
证明不了这一点 —— 那里面有你手调过的历史状态。

清掉测试目录不会有任何影响：

```bash
rm -rf /root/repro_test
```

---

## 10. 一句话总结

**路径 ① 的门槛只有两样：`librkllmrt.so` + `.rkllm` 模型。**
拿到这两样，`build/build_embodied_agent.sh` 编完就能对话了，
不需要摄像头、不需要麦克风、不需要 opencv、不需要 sherpa-onnx。

其余都是加分项。
