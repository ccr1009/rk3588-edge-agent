#!/bin/bash
# check_syntax.sh — 不依赖板子和 SDK 的编译检查
#
# 做什么：用 build/check_stubs/ 里的桩头文件，检查所有主程序的语法与类型。
#         能抓「改了字段名没改全」「API 用法和 SDK 对不上」这类错。
#
# 不能做什么：桩头文件没有真实现，编出来的东西**绝对不能上板**。
#            真正的板端验证还是要 g++ 实编 + 真机跑。
#
# 为什么值得有：改完代码、板子又不在手边的时候，这是唯一能当场发现
# 「我是不是把 rkllm_init 的参数改错了」的手段。本项目踩过
# 「改完一行都没编译过就提交」的亏（见 docs/OPEN_ISSUES #18）。
#
# 用法：
#   bash build/check_syntax.sh          # 检查，有错返回 1
#   bash build/check_syntax.sh -v       # 同上，但不吞 warning
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STUBS="$ROOT/build/check_stubs"
cd "$ROOT"

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

FAIL=0; PASS=0; SKIP=0
ok()   { printf '  [ OK ]   %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL]   %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  [SKIP]   %s\n' "$1"; SKIP=$((SKIP+1)); }

echo "=================================================================="
echo " 编译检查（桩头文件，无板子可用）"
echo "=================================================================="

command -v g++ >/dev/null 2>&1 || { echo "✗ 没有 g++"; exit 1; }

# ---- 1. 完全无外部依赖的三个：真编 ----
echo "[1/3] 无外部依赖（真编）"
for spec in \
    "edgevision_agent_server|agent/edgevision_agent_server.cpp|-lpthread" \
    "edgevision_patrol_daemon|agent/edgevision_patrol_daemon.cpp|-lpthread" \
    "voice_gateway|voice/voice_gateway.cpp|-lpthread -lutil"; do
    name="${spec%%|*}"; rest="${spec#*|}"; src="${rest%%|*}"; libs="${rest#*|}"
    out=$(g++ -O2 -std=c++17 -Wall -Wextra "$src" $libs -o "/tmp/_chk_$name" 2>&1)
    if [ $? -eq 0 ] && [ -z "$out" ]; then ok "$name（零告警）"
    elif [ -n "$out" ]; then
        # 只有 warning 也算通过，但列出来
        if echo "$out" | grep -q "error:"; then
            bad "$name"; echo "$out" | sed 's/^/        /' | head -6
        else
            ok "$name（有 warning）"
            [ $VERBOSE -eq 1 ] && echo "$out" | sed 's/^/        /' | head -6
        fi
    else bad "$name"; fi
done

# ---- 2. 需要 SDK 的：桩头文件语法检查 ----
echo "[2/3] 需要 SDK（桩头文件语法检查）"
for spec in \
    "rkllm_embodied_agent|agent/rkllm_embodied_agent.cpp" \
    "tts_daemon|voice/tts_daemon.cpp"; do
    name="${spec%%|*}"; src="${spec#*|}"
    out=$(g++ -O2 -std=c++17 -Wall -fsyntax-only -I"$STUBS" "$src" 2>&1)
    # unused parameter 是桩头文件带来的噪声，不算错
    real=$(echo "$out" | grep -E "error:" )
    if [ -z "$real" ]; then ok "$name（桩头文件通过）"
    else bad "$name"; echo "$real" | sed 's/^/        /' | head -6; fi
done

# ---- 3. 需要 opencv 的：有就检查，没有就跳过 ----
echo "[3/3] 需要 opencv4（有才检查）"
if pkg-config --exists opencv4 2>/dev/null; then
    for spec in \
        "edgevision_gateway|vision/edgevision_gateway.cpp" \
        "edgevision_preview_real|vision/edgevision_preview_real.cpp"; do
        name="${spec%%|*}"; src="${spec#*|}"
        out=$(g++ -O2 -std=c++17 -fsyntax-only -DENABLE_RKNN \
              -Iinclude -I3rdparty/rknn_api/include \
              $(pkg-config --cflags opencv4) "$src" 2>&1 | grep -E "error:")
        if [ -z "$out" ]; then ok "$name"; else bad "$name"; echo "$out" | head -4; fi
    done
else
    skip "edgevision_gateway / edgevision_preview_real（无 opencv4）"
    echo "         → 在板子上跑: apt-get install -y libopencv-dev"
fi

echo "=================================================================="
echo " 汇总: $PASS 通过 / $FAIL 失败 / $SKIP 跳过"
if [ $FAIL -gt 0 ]; then
    echo " ⚠️  桩头文件检查只证明语法和类型对，不证明板端能跑。"
    echo "    真验证仍需: 板上 g++ 实编 + 真机运行"
fi
echo "=================================================================="
exit $([ $FAIL -gt 0 ] && echo 1 || echo 0)
