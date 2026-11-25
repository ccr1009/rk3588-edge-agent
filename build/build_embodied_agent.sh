#!/bin/bash
# build_embodied_agent.sh — 板端原生编译具身 Agent
#
# 为什么必须板端原生编译：交叉编译有 glibc 风险（PC 端 2.35 vs 板子 Debian 11 的 2.31）。
#
# 依赖（需自己准备，不进仓库）：
#   $DEPLOY/rkllm.h          ← RKLLM SDK 头文件
#   $DEPLOY/librkllmrt.so    ← RKLLM runtime（v1.3.1 实测可用）
#   $DEPLOY/qwen3.5-2b_w8a8_rk3588.rkllm  ← 量化后的模型（约 2.98 GB）
#   $DEPLOY/rkllm.h 与 librkllmrt.so 来自 Rockchip RKLLM SDK；
#   模型用 rkllm-toolkit 从 Qwen3.5-2B 转换而来，见 REPRODUCE.md。
#
# 用法：
#   bash build/build_embodied_agent.sh              # 用默认 $DEPLOY=/root/rkllm_deploy
#   DEPLOY=/root/mydir bash build/build_embodied_agent.sh
#   bash build/build_embodied_agent.sh "现在板子温度多少"   # 编完直接跑一句
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOY="${DEPLOY:-/root/rkllm_deploy}"

[ -f "$DEPLOY/rkllm.h" ] || {
    echo "[-] 缺 $DEPLOY/rkllm.h（RKLLM SDK 头文件）"
    echo "    从 Rockchip RKLLM SDK 取，或用 DEPLOY= 指定放它的目录。见 REPRODUCE.md"
    exit 1
}
[ -f "$DEPLOY/librkllmrt.so" ] || {
    echo "[-] 缺 $DEPLOY/librkllmrt.so（RKLLM runtime）"
    exit 1
}

echo "=== 正在板端原生编译 rkllm_embodied_agent ==="
mkdir -p "$DEPLOY"
# 源码先规范化行尾：Windows 的 \r 会让 g++ 报 stray '\r'
tr -d '\r' < "$ROOT/agent/rkllm_embodied_agent.cpp" > "$DEPLOY/rkllm_embodied_agent.cpp.build"
cd "$DEPLOY"
g++ -O2 rkllm_embodied_agent.cpp.build \
    -I. -L. -lrkllmrt -Wl,-rpath,'$ORIGIN' \
    -o rkllm_embodied_agent
mv -f rkllm_embodied_agent.cpp.build rkllm_embodied_agent.cpp
echo "=== 编译成功: $DEPLOY/rkllm_embodied_agent ==="

if [ $# -gt 0 ]; then
    echo "=== 直接跑一次：$* ==="
    exec "$DEPLOY/rkllm_embodied_agent" "$@"
fi
echo "运行: cd $DEPLOY && ./rkllm_embodied_agent"
