#!/bin/bash
# 板上原生编译 9000 推流网关（edgevision.service 跑的就是这个二进制）
#
# 用法（在本仓库任意位置调用都行）：
#   bash build/build_w4_gateway.sh              # 编到本脚本同级目录
#   OUT=/root/lab bash build/build_w4_gateway.sh  # 指定输出目录
#
# 依赖（都在本仓库内，不需要外部仓库）：
#   vision/edgevision_gateway.cpp
#   src/rknn_engine_dfl_free.cpp     ← 2026-11-25 从 deploy/cpp 复制进来
#   src/postprocess_dfl_free.cpp
#   include/                          ← 4 个头文件
#   3rdparty/rknn_api/                ← rknn_api.h + librknnrt.so
# 系统依赖：opencv4（板端 4.5.1）
#
# ⚠️ 板端二进制名为什么还叫 w4_edgevision_gateway：
#   edgevision.service 的 ExecStart 和多个排查脚本的 pgrep -f 依赖这个名字。
#   仓库里的源文件名已去掉 w4_ 前缀（它早就不是第 4 周练习了），
#   但**二进制名不动**，避免打断既有部署。用 OUT 指定输出目录即可。
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT}"
mkdir -p "$OUT"
BIN="$OUT/w4_edgevision_gateway"

echo "[*] 编译 EdgeVision 9000 网关 → $BIN"

# ⚠️ 2026-11-20 修：本脚本原版缺两样东西，照它编译会出一个"看起来正常、
#    实际没跑 NPU"的二进制 —— 属于"假数据"的变种形态：
#
#   ① 缺 `-DENABLE_RKNN`：src/rknn_engine_dfl_free.cpp 里所有真 RKNN 调用
#      都包在 `#ifdef ENABLE_RKNN` 内，没定义就编成 x86 桩，
#      启动日志打 `[!] x86 Stub Mode (no NPU)`、NPU 耗时恒 0ms、
#      推流出去全是"检出 0 目标"。画面/端口/协议全都正常，只有结果是假的。
#
#   ② 缺引擎与后处理源文件：`undefined reference to RKNNEngineDflFree::...`
#
#   验证方法（编完必查，两条都要过）：
#      strings 二进制 | grep -c "x86 Stub Mode"   → 必须 0
#      nm -C  二进制 | grep -c  cam_read          → 必须 ≥1（断帧加固在）
g++ -O2 -std=c++17 -DENABLE_RKNN \
    "$ROOT/vision/edgevision_gateway.cpp" \
    "$ROOT/src/rknn_engine_dfl_free.cpp" \
    "$ROOT/src/postprocess_dfl_free.cpp" \
    -o "$BIN" \
    -I"$ROOT/include" \
    -I"$ROOT/3rdparty/rknn_api/include" \
    -L"$ROOT/3rdparty/rknn_api/lib" \
    $(pkg-config --cflags --libs opencv4 2>/dev/null \
      || echo "-I/usr/include/opencv4 -lopencv_core -lopencv_videoio -lopencv_imgproc") \
    -lrknnrt -lpthread -Wl,-rpath,'$ORIGIN'

if strings "$BIN" | grep -q "x86 Stub Mode"; then
    echo "[-] 致命：编出的是 x86 桩，没有真 NPU。检查 -DENABLE_RKNN。"
    exit 1
fi

if ! nm -C "$BIN" 2>/dev/null | grep -q cam_read; then
    echo "[-] 警告：二进制里没有 cam_read，断帧保护可能未生效"
    exit 1
fi

echo "[+] 编译成功: $BIN"
ls -lh "$BIN"
