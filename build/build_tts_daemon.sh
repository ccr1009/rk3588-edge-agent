#!/bin/bash
# build_tts_daemon.sh — 板端原生编译 TTS 常驻守护
#
# 依赖（需自己准备，不进仓库）：
#   $SHERPA_ROOT/sherpa-onnx/c-api/c-api.h   ← sherpa-onnx C API 头
#   $SHERPA_ROOT/**/libsherpa-onnx-c-api.a   ← 静态库（随 sherpa-onnx 静态包提供）
#   /root/asr/tts-fanchen/                   ← VITS 模型目录（model/tokens/lexicon/dict）
#
# 用法：
#   SHERPA_ROOT=/root/asr/sherpa-onnx-v1.12.12-linux-aarch64-static \
#     bash build/build_tts_daemon.sh
#
# 说明：只在需要「首段合成 1s」时才要它；不装也能跑，语音网关会降级成
#       fork/exec 每段多花约 3.7 s 加载模型。
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHERPA_ROOT="${SHERPA_ROOT:-/root/asr/sherpa-onnx-v1.12.12-linux-aarch64-static}"
OUT="${OUT:-$ROOT}"
BIN="$OUT/tts_daemon"

HDR="$SHERPA_ROOT/sherpa-onnx/c-api/c-api.h"
[ -f "$HDR" ] || {
    echo "[-] 缺 $HDR"
    echo "    把 SHERPA_ROOT 指向 sherpa-onnx 静态包解压目录。见 REPRODUCE.md"
    exit 1
}

# 静态包里库的位置各版本不一，这里按已知几种布局依次找
LIB=""
for cand in \
    "$SHERPA_ROOT/lib/libsherpa-onnx-c-api.a" \
    "$SHERPA_ROOT/build/lib/libsherpa-onnx-c-api.a" \
    "$SHERPA_ROOT/libsherpa-onnx-c-api.a"; do
    [ -f "$cand" ] && { LIB="$cand"; break; }
done
[ -n "$LIB" ] || {
    echo "[-] 找不到 libsherpa-onnx-c-api.a，请用 -L 手动指定"
    find "$SHERPA_ROOT" -name 'libsherpa-onnx*.a' 2>/dev/null | head -5
    exit 1
}

echo "[*] 编译 TTS 常驻守护 → $BIN"
g++ -O2 -std=c++17 \
    "$ROOT/voice/tts_daemon.cpp" \
    -o "$BIN" \
    -I"$SHERPA_ROOT" \
    -L"$(dirname "$LIB")" \
    -lsherpa-onnx-c-api \
    -lpthread -ldl

echo "[+] 编译成功: $BIN"
echo "    socket: /tmp/tts_daemon.sock    模型: /root/asr/tts-fanchen"
