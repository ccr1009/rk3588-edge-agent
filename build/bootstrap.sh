#!/bin/bash
# bootstrap.sh — 从零装到能跑
#
# 做四件事：
#   1) 检查硬件/系统前提（架构、核数、内存、NPU 驱动）
#   2) 检查那三个"不在仓库里"的东西，缺什么就明确说清缺什么、去哪拿
#   3) 按依赖从少到多逐个编译，编一个报一个
#   4) 编完给下一步的确切命令
#
# 用法：
#   bash build/bootstrap.sh            # 全量检查 + 编译能编的
#   bash build/bootstrap.sh --check    # 只检查，不编译
#   bash build/bootstrap.sh --text     # 只准备路径 ①（纯文本 Agent）
#
# 设计原则：**绝不静默跳过**。缺依赖时打印"缺什么 + 怎么办"，而不是跳过去
# 让人以为编过了 —— 这个项目里最难查的 bug 全是"上一步静默失败"。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CHECK_ONLY=0
TEXT_ONLY=0
for a in "$@"; do
    case "$a" in
        --check) CHECK_ONLY=1 ;;
        --text)  TEXT_ONLY=1 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    esac
done

PASS=0; WARN=0; FAIL=0
ok()   { printf '  [ OK ]   %s\n' "$1"; PASS=$((PASS+1)); }
warn() { printf '  [WARN]   %s\n' "$1"; WARN=$((WARN+1)); }
bad()  { printf '  [FAIL]   %s\n' "$1"; FAIL=$((FAIL+1)); }
line() { printf '%s\n' "------------------------------------------------------------------"; }

echo "=================================================================="
echo " RK3588 端侧 Agent — 一键装配"
echo " 仓库: $ROOT"
echo " 时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================================="

# ================================================================ 1. 前提
line; echo "[1/4] 硬件与系统前提"; line

ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then ok "架构 aarch64"
else bad "架构是 $ARCH，不是 aarch64 —— 本项目只能在 ARM 板子上跑"; fi

CORES=$(nproc 2>/dev/null || echo 0)
if [ "$CORES" -ge 8 ]; then ok "CPU $CORES 核"
else warn "CPU 只有 $CORES 核（RK3588 应为 8），小核跑大模型会很慢"; fi

MEM_GB=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}')
if [ -n "${MEM_GB:-}" ] && [ "$MEM_GB" -ge 7 ]; then ok "内存 ${MEM_GB} GB"
else warn "内存 ${MEM_GB:-未知} GB（模型约 2.98 GB + 运行时，建议 ≥ 7 GB）"; fi

if [ -e /sys/kernel/debug/rknpu/version ]; then
    ok "NPU 驱动: $(cat /sys/kernel/debug/rknpu/version 2>/dev/null)"
else
    warn "查不到 /sys/kernel/debug/rknpu/version（可能没挂 debugfs，或 NPU 驱动未装）"
fi

if command -v g++ >/dev/null 2>&1; then ok "g++ $(g++ -dumpversion)"
else bad "没有 g++，先装: apt-get install -y build-essential"; fi

# ================================================================ 2. 外部依赖
line; echo "[2/4] 外部依赖（这三样不在仓库里）"; line

DEPLOY="${DEPLOY:-/root/rkllm_deploy}"
NEED_MODEL=0

# ---- 2.1 RKLLM runtime ----
if [ -f "$DEPLOY/rkllm.h" ] && [ -f "$DEPLOY/librkllmrt.so" ]; then
    ok "RKLLM runtime: $DEPLOY/librkllmrt.so"
else
    bad "缺 RKLLM runtime（$DEPLOY/rkllm.h + librkllmrt.so）"
    echo "         → 从 Rockchip RKLLM SDK 取 v1.3.1，放到 $DEPLOY/"
    echo "         → 没有它 Agent 编不出来，路径 ① 走不了"
    NEED_MODEL=1
fi

# ---- 2.2 大模型 ----
if ls "$DEPLOY"/*.rkllm >/dev/null 2>&1; then
    ok "大模型: $(ls -lh "$DEPLOY"/*.rkllm | awk '{print $9" ("$5")"}' | head -1)"
else
    bad "缺 .rkllm 模型（约 2.98 GB）"
    echo "         → 用 rkllm-toolkit 从 Qwen3.5-2B 转，见 REPRODUCE.md 第 2.2 节"
    echo "         → 这是本仓库已知的复现断点（转换脚本没留下来）"
    NEED_MODEL=1
fi

# ---- 2.3 声卡（只在语音路径需要）----
if [ -d /dev/snd ]; then
    ok "声卡: $(arecord -l 2>/dev/null | grep -c '^card') 个采集设备"
else
    warn "无 /dev/snd —— 语音路径 ③ 不可用（路径 ①② 不受影响）"
fi

# ---- 2.4 opencv（只在视觉路径需要）----
if pkg-config --exists opencv4 2>/dev/null; then
    ok "opencv4 $(pkg-config --modversion opencv4)"
else
    warn "无 opencv4 —— 9000 网关和 8080 预览编不了（apt-get install -y libopencv-dev）"
fi

# ---- 2.5 自带依赖自检 ----
if [ -f "$ROOT/3rdparty/rknn_api/lib/librknnrt.so" ]; then
    ok "librknnrt.so 已自带（$(du -h "$ROOT/3rdparty/rknn_api/lib/librknnrt.so" | cut -f1)）"
else
    bad "仓库里少了 3rdparty/rknn_api/lib/librknnrt.so"
fi
if [ -f "$ROOT/include/rknn_engine_dfl_free.h" ] && [ -f "$ROOT/src/rknn_engine_dfl_free.cpp" ]; then
    ok "视觉引擎源码与头文件已自带"
else
    bad "仓库里少了 include/ 或 src/ —— 克隆不完整？"
fi

# ---- 2.6 sherpa（只在 TTS 需要）----
SHERPA_ROOT="${SHERPA_ROOT:-/root/asr/sherpa-onnx-v1.12.12-linux-aarch64-static}"
if [ -f "$SHERPA_ROOT/sherpa-onnx/c-api/c-api.h" ]; then
    ok "sherpa-onnx: $SHERPA_ROOT"
else
    warn "无 sherpa-onnx 静态包 —— tts_daemon 编不了（不影响其余）"
fi

if [ $CHECK_ONLY -eq 1 ]; then
    line
    echo "检查完成：$PASS OK / $WARN WARN / $FAIL FAIL"
    line
    exit $([ $FAIL -gt 0 ] && echo 1 || echo 0)
fi

# ================================================================ 3. 编译
line; echo "[3/4] 编译"; line

BUILT=(); SKIPPED=()

try_build() {   # $1=名字  $2=命令
    printf '  → %-24s ' "$1"
    if out=$(eval "$2" 2>&1); then
        echo "✓"; BUILT+=("$1")
    else
        echo "✗"
        echo "$out" | sed 's/^/        /' | tail -8
        SKIPPED+=("$1")
    fi
}

# 零外部依赖的三个，先编
try_build "edgevision_agent_server" "bash build/build_agent_server.sh"
try_build "edgevision_patrol_daemon" "bash build/build_patrol_daemon.sh"
try_build "voice_gateway"            "bash build/build_voice_gateway.sh"

if [ $TEXT_ONLY -eq 0 ]; then
    # 需要 RKLLM
    if [ $NEED_MODEL -eq 0 ]; then
        try_build "rkllm_embodied_agent" "DEPLOY=$DEPLOY bash build/build_embodied_agent.sh"
    else
        printf '  → %-24s 跳过（缺 RKLLM runtime 或模型）\n' "rkllm_embodied_agent"
        SKIPPED+=("rkllm_embodied_agent")
    fi

    # 需要 opencv + rknnrt
    if pkg-config --exists opencv4 2>/dev/null; then
        try_build "w4_edgevision_gateway" "OUT=/root/lab bash build/build_w4_gateway.sh"
        try_build "w4_edgevision_preview_real" "OUT=/root/lab bash build/build_preview.sh"
    else
        printf '  → %-24s 跳过（缺 opencv4）\n' "9000 网关 / 8080 预览"
        SKIPPED+=("gateway" "preview")
    fi

    # 需要 sherpa
    if [ -f "$SHERPA_ROOT/sherpa-onnx/c-api/c-api.h" ]; then
        try_build "tts_daemon" "OUT=/root SHERPA_ROOT=$SHERPA_ROOT bash build/build_tts_daemon.sh"
    else
        printf '  → %-24s 跳过（缺 sherpa-onnx）\n' "tts_daemon"
        SKIPPED+=("tts_daemon")
    fi
else
    echo "  （--text 模式：只准备路径 ①，其余跳过）"
fi

# ================================================================ 4. 下一步
line; echo "[4/4] 下一步该做什么"; line

echo "  已编译: ${BUILT[*]:-无}"
[ ${#SKIPPED[@]} -gt 0 ] && echo "  未编译: ${SKIPPED[*]}"

echo ""
if [ $NEED_MODEL -eq 0 ]; then
    cat <<EOF
  ✅ Agent 可以跑了。验证（不需要摄像头/麦克风）：

      cd $DEPLOY && ./rkllm_embodied_agent
      # 然后输入：现在板子温度多少
      # 期望：模型自己调 get_system_health，读出真实温度再回答

  或者完全不用交互：

      ./voice_gateway --ask "现在板子温度多少"
EOF
else
    cat <<EOF
  ⛔ 缺的东西没到位，Agent 还跑不了。补齐这两样：

      1. RKLLM SDK → $DEPLOY/rkllm.h + librkllmrt.so
      2. .rkllm 模型 → $DEPLOY/qwen3.5-2b_w8a8_rk3588.rkllm

  细节见 REPRODUCE.md 第 2 节。但你现在**已经能验证工具链**：

      bash tools/01_probe.sh                    # 硬件探针
      ./edgevision_agent_server                 # 8088 控制面，无模型也能跑
      curl http://127.0.0.1:8088/api/status     # 读真实温度/NPU/内存
EOF
fi

echo ""
echo "=================================================================="
echo " 汇总: $PASS OK / $WARN WARN / $FAIL FAIL   编译成功 ${#BUILT[@]} / 跳过 ${#SKIPPED[@]}"
echo " 完整说明: REPRODUCE.md"
echo "=================================================================="
