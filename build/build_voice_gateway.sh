#!/bin/bash
# build_voice_gateway.sh — 板端原生编译语音编排网关
#
# 依赖：只需 std + pthread + util，不链接 RKNN / RKLLM / sherpa。
#       ASR/TTS 都是 fork/exec 子进程，所以网关本身能独立编出来。
#
# 运行时前置（可选，缺了会降级）：
#   /root/asr/...               ASR/TTS 模型（缺了自动进纯文本模式，不会崩）
#   /root/tts_daemon             TTS 常驻守护（缺了每段多花 3.7s）
#   /root/rkllm_deploy/rkllm_embodied_agent    Agent（缺了只剩"听到你说X"回显）
#
# 用法：
#   bash build/build_voice_gateway.sh
#   OUT=/root bash build/build_voice_gateway.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT}"
BIN="$OUT/voice_gateway"

echo "[*] 编译语音网关 → $BIN"
g++ -O2 -std=c++17 -Wall -Wextra \
    "$ROOT/voice/voice_gateway.cpp" \
    -lpthread -lutil \
    -o "$BIN"

echo "[+] 编译成功: $BIN"
echo "    无麦克风时会自动降级为纯文本模式；也可直接:"
echo "      $BIN --ask \"现在板子温度多少\""
