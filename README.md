# RK3588 端侧具身 Agent + 视觉/语音链路

一块 RK3588 单板上的完整端侧 AI 项目：**Qwen3.5-2B 大模型 + 硬件 Tool Calling 的具身 Agent**，
配一条 YOLOv8 INT8 的 9000 TCP 推流网关、一条语音交互链路、一个巡检守护。

**全部离线，不依赖任何云端 API。** 6 个硬件工具直接读写 sysfs / DRM / POSIX socket。

> **想复现？先看 [`REPRODUCE.md`](REPRODUCE.md)。**
> 从空板开始的每一步、每个模型去哪拿、每步该看到什么，都写在那份文件里。
> 只想最快看到东西跑起来 → 走「无麦克风」那条路，它只需要模型和 runtime 两样。

> ⚠️ **目录名叫 `lab`（历史遗留），但放的是生产线代码，不是练习。**
>
> 本仓库是一个独立分发的子集，源自主项目 `rk3588-edge-ai` 的 `lab/`。
> 已经补齐了编译它所需的头文件、引擎源码和 `librknnrt.so`，
> 所以**可以单独 clone 和编译**，不再需要额外的兄弟仓库。

> 2026-11-02 重排：原先 72 个文件全部平铺在根下，找东西靠翻。
> 现在按职责分成 12 个子目录，主要入口见下面第一节。

> 📖 **构建与部署**：所有编译脚本在 [`build/`](build/)，统一用 `dirname "$0"` 定位仓库根，
> 从任何目录调用都成立。`build/bootstrap.sh` 是「从零装到能跑」的一键入口。

---

## 一、按职责找东西

| 我要改… | 去这里 |
| :--- | :--- |
| Agent 的工具、prompt、护栏 | [`agent/`](agent/) |
| 语音识别/合成/唤醒 | [`voice/`](voice/) |
| 9000 网关、8080 预览 | [`vision/`](vision/) |
| 回归测试、探针、客户端 | [`tests/`](tests/) |
| systemd unit 文件 | [`services/`](services/) |
| 编译脚本、一键上线 | [`build/`](build/) |
| 历史实验草稿（不要改） | [`drafts/`](drafts/) |
| 攻坚工具源码 | [`tools/`](tools/) |
| 一次性调试脚本 | [`scripts/`](scripts/) |

---

## 二、六个目录的详细内容

### `agent/` — 边缘智能体（3 个源文件 + 3 个诊断脚本）

| 文件 | 是什么 | 部署到板上 |
| :--- | :--- | :--- |
| `rkllm_embodied_agent.cpp` | **Agent 主体**：7 个硬件工具、sys_prompt、快速通道、护栏 | `/root/rkllm_deploy/rkllm_embodied_agent.cpp` |
| `edgevision_patrol_daemon.cpp` | **巡检守护快层**：5 s 周期采温度/NPU/视觉帧，迟滞状态机控 LED，**刻意不加载 LLM** | `/root/lab/edgevision_patrol_daemon` |
| `edgevision_agent_server.cpp` | 8088 HTTP/JSON RPC 控制面 | 单独 `g++`，见文件头注释 |
| `diag_patrol_launch.sh` | 守护启动失败诊断 | `/root/` |
| `verify_state.sh` | 验证运行态快照是否真实 | `/root/` |
| `probe_led_hardware.sh` | 探针：LED heartbeat 是否真的出光 | `/root/` |

> **这 7 个工具**（`agent/rkllm_embodied_agent.cpp` 的 schema 里数得出来）：
> `get_system_health` / `get_led_status` / `control_led` / `get_vision_telemetry` /
> `get_patrol_events` / `get_patrol_status` / `control_service`

### `voice/` — 语音交互

| 文件 | 是什么 |
| :--- | :--- |
| `voice_gateway.cpp` | **语音编排**：ASR 子进程、软唤醒、半双工、TTS 分段播报、fork Agent |
| `tts_daemon.cpp` | **TTS 常驻守护**（纯 CPU 推理，不碰 ALSA/RKNN），首段合成 1 s 靠它 |
| `voice_start.sh` | 启停脚本（含 `Speaker on`、`fuser -k` 清麦克风） |

### `vision/` — 视觉底座（**全项目的脊柱**）

| 文件 | 是什么 |
| :--- | :--- |
| `edgevision_gateway.cpp` | **9000 TCP 定长帧推流网关**（248 B/帧），`edgevision.service` 跑的就是它 |
| `edgevision_preview_real.cpp` | 8080 MJPEG 实时预览（检测框 + 3D 棱边 + BEV 小地图） |
| `cam_stream_server.cpp` | 8080 的另一实现（裸 V4L2，学习期） |
| `patch_gateway_dflfree.py` | 把 DFL-Free 后处理打进网关的补丁（历史工具） |

> ⚠️ **9000 网关不在 `deploy/cpp` 里。** `deploy/cpp` 的 6 个 target 没有一个是网关，
> 那些只做单张 jpg / 看板。网关源码在这里，靠 `build/build_w4_gateway.sh` 编译。
> **2026-11-25 起本仓库自包含**：引擎与后处理源码已复制进 `src/`，
> 头文件在 `include/`，`librknnrt.so` 在 `3rdparty/rknn_api/lib/`，
> 不再依赖兄弟仓库 `deploy/cpp`。
>
> **2026-11-02 已去掉 `w4_` 前缀**（原名 `w4_edgevision_gateway.cpp`）：它第 4 周写，
> 但早已是项目主线，不是练习。改名后仓库里叫 `edgevision_gateway.cpp`。
> **板端二进制仍叫 `w4_edgevision_gateway` 不变**——
> 因为 `edgevision.service` 的 `ExecStart` 和多个排查脚本的 `pgrep -f` 依赖这个名字。
> 编译时用 `OUT=/root/lab bash build/build_w4_gateway.sh` 指定输出目录即可。

### `tests/` — 自测工装与客户端（13 个）

**改完代码必须跑的四个**：

| 文件 | 是什么 |
| :--- | :--- |
| `regress.py` | **回归 20 条**：守护已知行为，期望词 + 禁止词双向断言 |
| `explore.py` | **探索 15 项**：撞未知边界（注入 / 矛盾 / 越权 / 假成功） |
| `loop_check.sh` | **声学回路连通性自检**：不过就退出，堵死"没测量却产出数字" |
| `test_e2e.sh` | 语音端到端自测（板子自己说给自己听） |

**其余**：

| 文件 | 是什么 |
| :--- | :--- |
| `bench_voice.sh` | 唤醒词命中率基准 |
| `bench_params.sh` | 参数扫描（`-O2/-O3` × 上下文长度） |
| `test_kws.sh` | 唤醒词手动实测（**独占麦克风**，跑前必须停网关） |
| `agent_multistep_demo.py` | 多步演示闭环编排器（纯标准库） |
| `agent_regression_test.py` | PC 端回归测试器 |
| `bench_contention_sampler.py` | NPU 竞争实测采样器 |
| `edge_agent_client.py` | PC 端 Agent 交互客户端 |
| `pc_client_viewer.py` | PC 端 9000 推流查看器 |
| `run_agent_test.py` | 板端 Agent 测试驱动 |

### `services/` — systemd unit（6 个 .service + 4 个配置）

| 文件 | 装到板上 |
| :--- | :--- |
| `voice-gateway.service` | `/etc/systemd/system/`（**含 `Conflicts=edgevision.service`**） |
| `tts-daemon.service` | `/etc/systemd/system/` |
| `edgevision-dashboard.service` | `/etc/systemd/system/`（读 mp4，**不占摄像头**） |
| `edgevision-dashboard-cam.service` | `/etc/systemd/system/`（**8090 摄像头模式，2026-11-12 新增**，占摄像头） |
| `edgevision-dashboard-cam.default` | `/etc/default/`（`DASH_CAM` / `DASH_PORT`） |
| `edgevision-preview.service` | `/etc/systemd/system/`（**8080 预览，2026-11-12 新增**，占摄像头） |
| `edgevision-preview.default` | `/etc/default/`（`PREVIEW_CAM` / `PREVIEW_CONF`） |
| `edgevision-patrol.service` | `/etc/systemd/system/` |
| `edgevision-patrol.default` | `/etc/default/`（`PATROL_ARGS`） |
| `edgevision-cam2.conf` | `/etc/systemd/system/edgevision.service.d/cam2.conf`（drop-in，把网关从坏 cam1 切 cam2） |

> **为什么 preview 也用 unit**：2026-11-12 之前它是手动进程，`pkill` 停不掉
> （SIGTERM 卡在 `pthread_join`，HTTP 线程阻塞在 `accept()`，双死锁），
> 而且 Agent 完全管不到。unit 里 `KillSignal=SIGKILL` + `SuccessExitStatus=SIGKILL`
> 两行配合，既不卡死、`stop` 后状态也正确（`inactive` 而非 `failed`）。

### `build/` — 编译与上线

| 文件 | 干什么 |
| :--- | :--- |
| `bootstrap.sh` | **从零装到能跑**：建目录 → 检查依赖 → 逐个编译 → 报缺什么 |
| `check_syntax.sh` | **无板子可用的编译检查**：用 `check_stubs/` 桩头文件检查 5 个主程序的语法与类型 |
| `deploy.sh` | **一条命令上线**：同步 → 板上编译 → 可选重启。只覆盖 Agent 与语音网关两个源文件 |
| `build_embodied_agent.sh` | 板上编译 Agent（需 RKLLM SDK） |
| `build_voice_gateway.sh` | 板上编译语音网关（无外部依赖） |
| `build_agent_server.sh` | 板上编译 8088 控制面 |
| `build_patrol_daemon.sh` | 板上编译巡检守护 |
| `build_w4_gateway.sh` | 板上编译 9000 网关（需 opencv4 + rknnrt） |
| `build_preview.sh` | 板上编译 8080 预览（需 opencv4 + rknnrt） |
| `build_tts_daemon.sh` | 板上编译 TTS 常驻守护（需 sherpa-onnx 静态包） |
| `build_and_run_agent.sh` | 编译并运行 `test_tools2`（旧测试） |

所有 `build_*.sh` 都用 `dirname "$0"` 定位仓库根，**从任何目录调用都行**；
输出目录用 `OUT=` 覆盖，默认落在仓库根。

> ⚠️ **`deploy.sh` 覆盖不全**：它只管 Agent 和语音网关。改网关（9000）、巡检守护、
> TTS、预览页**它不管**，得用对应的 `build_*.sh`。这是当前的真实缺口。

### 仓库根新增的目录（2026-11-25，为了自包含）

| 目录 | 是什么 | 来源 |
| :--- | :--- | :--- |
| `include/` | 视觉引擎与后处理的 4 个头文件 | 原 `rk3588-edge-ai/deploy/cpp/include/` |
| `src/` | 引擎与后处理实现（3 个 .cpp） | 原 `deploy/cpp/src/` |
| `3rdparty/rknn_api/` | `rknn_api.h` + `librknnrt.so`（7 MB） | 原 `deploy/cpp/3rdparty/` |
| `build/check_stubs/` | 桩头文件（`rkllm.h`、sherpa `c-api.h`），**只用于无板子时的编译检查，不能上板** | 手写，按真实调用面声明 |


### `drafts/` — 历史实验草稿（31 个，**不要改**）

10-20 ~ 10-27 攻坚期的一次性脚本。**结论已固化进 `docs/`**，留着只为查历史：

- `_p0_*`（7 个）：Agent 工具层 P0 修复期，结论在 `docs/p0_smoke_evidence.md`
- `_p6_*`（3 个）：task-6 编译/冒烟
- `bench_mjpg_decode*.cpp`、`bench_cam_fps*.cpp`：MPP 硬解与摄像头帧率攻坚
- `check_*.cpp` / `find_nonzero.cpp` / `inspect_anchor.cpp` / `probe_scores.cpp` / `test_*.cpp`：INT8 量化与后处理调试
- `w4_d23_signal.cpp` / `w4_d24_epoll.cpp`：第 4 周学习练习（信号 / epoll）
- `w4_edgevision_preview.cpp`：8080 预览的旧版本
- `*.from_board`：从板子回拉的临时副本

### `tools/` — 攻坚工具源码（51 个）｜`scripts/` — 一次性脚本（26 + 15 个）

见各自目录的 README。都是从板端 `/root/lab/` 抢救回来的。

---

## 三、改了代码怎么上线

```bash
cd build
./deploy.sh agent            # 同步 + 编译，不重启
./deploy.sh agent --restart  # 同步 + 编译 + 重启语音网关（会等 70s 就绪）
./deploy.sh gateway          # 语音网关同理
```

`deploy.sh` 会**先编译再替换**：编译失败就保留旧二进制，不会把板子弄成不能跑。
它用 `dirname "$0"` 自己定位，**从任何目录调用都行**。

手动等价步骤（脚本就是干这个）：

```bash
scp agent/rkllm_embodied_agent.cpp rk3588:/root/rkllm_deploy/agent_new.cpp
ssh rk3588 'cd /root/rkllm_deploy && tr -d "\r" < agent_new.cpp > rkllm_embodied_agent.cpp \
  && g++ -O2 rkllm_embodied_agent.cpp -L. -lrkllmrt -Wl,-rpath=. -o .new \
  && mv -f .new rkllm_embodied_agent_p0'
```

**为什么要 `tr -d "\r"`**：Windows 行尾的 `\r` 会让 g++ 报 `stray '\r'`。脚本里已处理。

---

## 四、改完必须做的两件事

```bash
python3 /root/regress.py     # 20 条已知行为，必须全绿
python3 /root/explore.py     # 15 项边界探测，看有没有新发现
```

两个脚本都会**自己停网关腾出 NPU、跑完自动拉起**，约 2~3 分钟，不需要人参与。

改动涉及语音链路时，**先跑 `loop_check.sh`**：回路不通时 `bench_voice.sh` / `test_e2e.sh`
仍会产出具体数字（0/10 + 幻觉文本），那**不是失败，是没有测量**。

---

## 五、板子上的目录（**和仓库结构不同**）

| 板上路径 | 内容 |
| :--- | :--- |
| `/root/rkllm_deploy/` | Agent 二进制 + 2.98 GB 模型 + `rkllm.h` + 运行库 |
| `/root/voice_gateway` + `.cpp` | 语音网关二进制与源码副本 |
| `/root/tts_daemon` + `.cpp` | TTS 常驻服务 |
| `/root/lab/` | 网关/守护二进制、大量历史探针（243 个文件） |
| `/root/edgevision/` | 视觉引擎 `deploy/cpp/build_release/`、`data/videos/highway_traffic.mp4` |
| `/root/asr/` | 全部模型：Paraformer、VITS、KWS、VAD、两版 runtime |
| `/root/patrol/` | `patrol_events.log` / `llm_pending.jsonl` / `patrol_state.json` |

短名入口是**软链接**，全指向正本：

```bash
bp.sh -> bench_params.sh      bv.sh -> bench_voice.sh      te.sh -> test_e2e.sh
tk.sh -> test_kws.sh          vs.sh -> voice_start.sh
```

> 2026-10-31 之前它们是实体副本，各自漂移过。`vs.sh` 停在 10-29 版，
> 缺 `amixer -c 2 cset numid=16 on`——用它启动网关**完全没声音，日志却显示播放完成**，
> 正好掉回"假成功"那个坑。改成软链接后就再也漂不了。

---

## 六、源码与部署的漂移检查

```bash
# 本地算规范化 md5（去掉 \r），板上直接算
for f in agent/rkllm_embodied_agent.cpp voice/voice_gateway.cpp tests/regress.py tests/explore.py; do
  printf "%-38s %s\n" "$f" "$(tr -d '\r' < $f | md5sum | cut -c1-8)"
done
ssh rk3588 'md5sum /root/rkllm_deploy/rkllm_embodied_agent.cpp /root/voice_gateway.cpp'
```

md5 不一致 = 有人在板上直接改了代码，或者本地改了没部署。**以本地为准**。

---

## 七、这个仓库的已知问题

1. **`lab/` 这名字名不副实**（历史遗留）：9000 网关、Agent、语音、巡检守护四个
   **在跑的服务**都在这里。本仓库是从主项目 `lab/` 拆出来独立分发的，
   名字保持原样以对齐板端 `/root/lab/` 路径。**不做改名。**
2. ~~**`w4_` 前缀会误导**~~ **已在 2026-11-02 修掉**：`w4_edgevision_gateway.cpp` →
   `edgevision_gateway.cpp`，`w4_edgevision_preview_real.cpp` → `edgevision_preview_real.cpp`。
   板端二进制名保持 `w4_` 不变（unit 与 pgrep 依赖）。
   注意 `drafts/` 里还有 `w4_d23_signal.cpp`、`w4_d24_epoll.cpp`、`w4_edgevision_preview.cpp`
   ——**那几个是真的第 4 周练习与旧版本**，前缀是对的。
3. **`deploy.sh` 覆盖不全**：只同步 Agent 与语音网关，其余各有自己的 build 脚本。
4. **248 B 帧协议常量重复 3 份**：`agent/rkllm_embodied_agent.cpp`（约 539~554 行）、
   `tests/pc_client_viewer.py`、`agent/edgevision_patrol_daemon.cpp`
   （约 275~281 行）各写了一遍，没有共享头文件。改协议要同时改三处。
5. **`rkllm.h` / `librkllmrt.so` / `.rkllm` 模型不进仓库**（体积与许可原因）：
   Agent 编译前需自行准备，见 [`REPRODUCE.md`](REPRODUCE.md) 第 2 节。
   **这是复现的唯一硬门槛**，其余依赖本仓库已自带。
6. **`drafts/` 和 `tools/` 里有 10 个文件需要板端 MPP/RGA SDK 头**
   （`rk_mpi.h` / `rga.h` / `im2d.h`）。它们是一次性攻坚工具，
   **不影响 6 个主程序编译**，缺 SDK 时直接跳过即可。
