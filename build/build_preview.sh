#!/bin/bash
# 板上原生编译 8080 实时预览（检测框 + 3D 棱边 + BEV 小地图）
#
# 用法（在本仓库任意位置调用都行）：
#   bash build/build_preview.sh
#   OUT=/root/lab bash build/build_preview.sh
#
# 依赖（都在本仓库内）：
#   vision/edgevision_preview_real.cpp
#   src/postprocess_dfl_free.cpp
#   include/（postprocess_dfl_free.h、bev_projector.hpp）
#   3rdparty/rknn_api/
# 系统依赖：opencv4（含 videoio）
#
# ⚠️ 二进制名保持 w4_ 前缀：edgevision-preview.service 的 ExecStart 依赖它。
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT}"
mkdir -p "$OUT"
BIN="$OUT/w4_edgevision_preview_real"

echo "[*] 编译 RK3588 3D BEV 实时预览 → $BIN"

g++ -O2 -std=c++17 \
    "$ROOT/vision/edgevision_preview_real.cpp" \
    "$ROOT/src/postprocess_dfl_free.cpp" \
    -o "$BIN" \
    -I"$ROOT/include" \
    -I"$ROOT/3rdparty/rknn_api/include" \
    -L"$ROOT/3rdparty/rknn_api/lib" \
    $(pkg-config --cflags --libs opencv4) \
    -lrknnrt -lpthread -Wl,-rpath,'$ORIGIN'

echo "[+] 编译成功: $BIN"

# 断帧加固（2026-11-11）的验证：cam_read 必须在符号表里，
# 否则说明编的还是没 try/catch 的旧版，跑一会儿就会 Aborted。
if ! nm -C "$BIN" | grep -q cam_read; then
    echo "[-] 警告：二进制里没有 cam_read，断帧保护可能未生效"
    exit 1
fi
ls -lh "$BIN"
