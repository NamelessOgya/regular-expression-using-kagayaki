#!/usr/bin/env bash
# =============================================================
# run_sweep.sh  (CPU版)
# 1回分のCPUベンチマークスイープを実行してサマリーCSVを生成する。
#
# 使い方:
#   ./run_sweep.sh                                  # デフォルト出力先
#   ./run_sweep.sh ./data/wiki_plain.txt --out ./results/run_xxx/cpu/run1
# =============================================================
set -e

# --------------------------------------------------------
# 引数の解析
# --------------------------------------------------------
WIKI_FILE="./data/wiki_plain.txt"
OUT_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --out) OUT_DIR="$2"; shift 2 ;;
        *) WIKI_FILE="$1"; shift ;;
    esac
done

if [ ! -f "$WIKI_FILE" ]; then
    echo "[ERROR] Target file not found: $WIKI_FILE"
    echo "        Run ./setup_dataset.sh first."
    exit 1
fi

# 出力先が未指定の場合はタイムスタンプ付きデフォルト
TIMESTAMP=$(date +%Y%m%d_%H_%M_%S)
if [ -z "$OUT_DIR" ]; then
    OUT_DIR="./results/sweep_${TIMESTAMP}"
fi
mkdir -p "$OUT_DIR"

MANIFEST="${OUT_DIR}/manifest.txt"
SUMMARY="${OUT_DIR}/summary.csv"

# UTF-8 文字数を正確に取得
MAX_CHARS=$(python3 -c "
with open('$WIKI_FILE', encoding='utf-8', errors='ignore') as f:
    print(len(f.read()))
")

# サイズリスト: 100 → 1000 → 10000 → ... → MAX (10倍刻み)
SIZES=()
s=100
while [ "$s" -lt "$MAX_CHARS" ]; do
    SIZES+=("$s")
    s=$((s * 10))
done
SIZES+=("$MAX_CHARS")

BINARY="./run_benchmark.asan"

echo "=================================================="
echo " CPU Benchmark Sweep"
echo " Target : $WIKI_FILE  (~${MAX_CHARS} chars)"
echo " Sizes  : ${SIZES[*]}"
echo " Out    : $OUT_DIR"
echo "=================================================="

# --------------------------------------------------------
# ビルド
# --------------------------------------------------------
echo ""
echo "[Build] Compiling CPU benchmark binary..."
INC="-I./include -I./src/gpu/common -I./src/gpu/line_parallel -I./src/gpu/chunk_parallel"
CFLAGS_ASAN="-g -O1 -fsanitize=address -fno-omit-frame-pointer -Wall -Wextra"
LDFLAGS_ASAN="-fsanitize=address"

gcc $INC $CFLAGS_ASAN -c src/cpu/nfa_cpu.c     -o nfa_cpu.o
gcc $INC $CFLAGS_ASAN -c src/common/utils.c    -o utils.o
gcc $INC $CFLAGS_ASAN -c src/common/re2post.c  -o re2post.o
gcc $INC $CFLAGS_ASAN -c src/common/post2nfa.c -o post2nfa.o
gcc $INC $CFLAGS_ASAN -c app/run_benchmark.c   -o run_benchmark.o
gcc $LDFLAGS_ASAN nfa_cpu.o utils.o re2post.o post2nfa.o run_benchmark.o -o "$BINARY"
echo "[Build] OK -> $BINARY"

# --------------------------------------------------------
# サイズごとに実行
# --------------------------------------------------------
# run_benchmark.asan は ./results/results_<timestamp>.csv を生成するため
# 実行前後のファイル一覧差分で新規ファイルを特定してOUT_DIRにコピーする
mkdir -p "./results"

for size in "${SIZES[@]}"; do
    echo ""
    echo "----------------------------------------------"
    echo " [RUN] size = ${size} chars"
    echo "----------------------------------------------"

    ls ./results/results_*.csv 2>/dev/null | sort > /tmp/sweep_cpu_before.txt || true

    "$BINARY" "$WIKI_FILE" "$size"

    ls ./results/results_*.csv 2>/dev/null | sort > /tmp/sweep_cpu_after.txt || true
    NEW_FILE=$(comm -13 /tmp/sweep_cpu_before.txt /tmp/sweep_cpu_after.txt | head -1 || true)

    if [ -z "$NEW_FILE" ]; then
        NEW_FILE=$(ls -t ./results/results_*.csv 2>/dev/null | head -1 || true)
        echo "[WARN] Could not detect new file by diff; using latest: $NEW_FILE"
    fi

    if [ -n "$NEW_FILE" ]; then
        DEST="${OUT_DIR}/result_size${size}.csv"
        cp "$NEW_FILE" "$DEST"
        echo "${DEST}:${size}" >> "$MANIFEST"
        echo "[RUN] Saved -> $DEST"
    else
        echo "[ERROR] No result CSV found for size=${size}"
    fi
done

# --------------------------------------------------------
# サマリー CSV の生成 (Python)
# --------------------------------------------------------
echo ""
echo "[Summary] Aggregating results..."

python3 /app/scripts/aggregate_sweep.py "$MANIFEST" "$SUMMARY"

echo ""
echo "=================================================="
echo " CPU Sweep complete!"
echo " Summary : $SUMMARY"
echo "=================================================="
