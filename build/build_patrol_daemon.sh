#!/bin/bash
# build_patrol_daemon.sh — 板上原生编译巡检守护快层
#
# 为什么原生编译: 交叉编译有 glibc 风险(PC 端 2.35 vs 板子 Debian11 2.31), 一律板上 g++ 编译。
# 只依赖 pthread/std, 不链接 RKLLM —— 快层绝不加载大模型。
#
# 用法：
#   bash build/build_patrol_daemon.sh
#   OUT=/root/lab bash build/build_patrol_daemon.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT}"
mkdir -p "$OUT"

SRC="$ROOT/agent/edgevision_patrol_daemon.cpp"
BIN="$OUT/edgevision_patrol_daemon"

echo "[build] g++ -O2 -std=c++17 -Wall $SRC -lpthread -o $BIN"
g++ -O2 -std=c++17 -Wall "$SRC" -lpthread -o "$BIN"

echo "[build] OK -> $BIN"
echo "[note] 板端部署位置: /root/lab/edgevision_patrol_daemon"
