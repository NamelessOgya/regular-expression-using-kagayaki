#!/usr/bin/env bash
# =============================================================
# run_sweep_gpu.sh
# GPU版 ベンチマークスイープスクリプト
# 正規表現 × テキスト文字数のグリッドで GPU ベンチマークを実行し、
# 結果を results/sweep_gpu_<timestamp>.csv にまとめる。
#
# 使い方:
#   ./run_sweep_gpu.sh                        # wiki_plain.txt を対象に全サイズ実行
#   ./run_sweep_gpu.sh ./data/wiki_plain.txt  # ファイル指定
# =============================================================
set -e

# --------------------------------------------------------
# 引数の解析
# --------------------------------------------------------
WIKI_FILE="${1:-./data/wiki_plain.txt}"

if [ ! -f "$WIKI_FILE" ]; then
    echo "[ERROR] Target file not found: $WIKI_FILE"
    echo "        Run ./setup_dataset.sh first."
    exit 1
fi

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

BINARY="./run_benchmark_gpu.out"
TIMESTAMP=$(date +%Y%m%d_%H_%M_%S)
SWEEP_DIR="./results/sweep_gpu_${TIMESTAMP}"
SUMMARY="./results/sweep_gpu_${TIMESTAMP}.csv"
MANIFEST="${SWEEP_DIR}/manifest.txt"
mkdir -p "$SWEEP_DIR"

echo "=================================================="
echo " GPU Benchmark Sweep"
echo " Target : $WIKI_FILE  (~${MAX_CHARS} chars)"
echo " Sizes  : ${SIZES[*]}"
echo " Summary: $SUMMARY"
echo "=================================================="

# --------------------------------------------------------
# ビルド (GPU 比較モード: CPU + GPU Line + GPU Chunk)
# --------------------------------------------------------
echo ""
echo "[Build] Compiling GPU benchmark binary..."
INC="-I./include -I./src/gpu -I./src/gpu/common -I./src/gpu/line_parallel -I./src/gpu/chunk_parallel"
OPT="-O3"

nvcc $OPT -arch=sm_80 -DGPU_RUN $INC -c src/gpu/line_parallel/nfa_gpu_line.cu   -o nfa_gpu_line.o
nvcc $OPT -arch=sm_80 -DGPU_RUN $INC -c src/gpu/chunk_parallel/nfa_gpu_chunk.cu -o nfa_gpu_chunk.o
gcc  $OPT             -DGPU_RUN $INC -c src/cpu/nfa_cpu.c                        -o nfa_cpu_gpu.o
gcc  $OPT             -DGPU_RUN $INC -c src/common/utils.c                       -o utils_gpu.o
gcc  $OPT             -DGPU_RUN $INC -c src/common/re2post.c                     -o re2post_gpu.o
gcc  $OPT             -DGPU_RUN $INC -c src/common/post2nfa.c                    -o post2nfa_gpu.o
gcc  $OPT             -DGPU_RUN $INC -c app/run_benchmark.c                      -o run_benchmark_gpu.o
nvcc $OPT -arch=sm_80 \
    nfa_gpu_line.o nfa_gpu_chunk.o nfa_cpu_gpu.o \
    utils_gpu.o re2post_gpu.o post2nfa_gpu.o run_benchmark_gpu.o \
    -o "$BINARY"
echo "[Build] OK -> $BINARY"

# --------------------------------------------------------
# サイズごとに実行
# --------------------------------------------------------
for size in "${SIZES[@]}"; do
    echo ""
    echo "----------------------------------------------"
    echo " [RUN] size = ${size} chars"
    echo "----------------------------------------------"

    ls ./results/results_*.csv 2>/dev/null | sort > /tmp/sweep_gpu_before.txt || true

    "$BINARY" "$WIKI_FILE" "$size"

    ls ./results/results_*.csv 2>/dev/null | sort > /tmp/sweep_gpu_after.txt || true
    NEW_FILE=$(comm -13 /tmp/sweep_gpu_before.txt /tmp/sweep_gpu_after.txt | head -1 || true)

    if [ -z "$NEW_FILE" ]; then
        NEW_FILE=$(ls -t ./results/results_*.csv 2>/dev/null | head -1 || true)
        echo "[WARN] Could not detect new file by diff; using latest: $NEW_FILE"
    fi

    if [ -n "$NEW_FILE" ]; then
        DEST="${SWEEP_DIR}/result_size${size}.csv"
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
echo "[Summary] Aggregating results from $SWEEP_DIR ..."

python3 - "$MANIFEST" "$SUMMARY" << 'PYEOF'
import csv, os, sys

csv.field_size_limit(sys.maxsize)  # マッチ詳細フィールドが大きい場合の上限解除
manifest_path = sys.argv[1]
summary_path  = sys.argv[2]

rows = []
with open(manifest_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        colon_idx = line.rfind(":")
        filepath = line[:colon_idx]
        size = int(line[colon_idx + 1:])

        if not os.path.exists(filepath):
            print(f"[WARN] File not found: {filepath}", file=sys.stderr)
            continue

        with open(filepath, newline="", encoding="utf-8") as cf:
            reader = csv.reader(cf)
            next(reader)  # ヘッダーをスキップ
            for row in reader:
                if len(row) < 5:
                    continue
                regex       = row[0].strip().rstrip("\n\r")
                match_count = row[2].strip()
                exec_time   = row[4].strip()
                note = "TIMEOUT" if exec_time == "300.000000" else ""
                rows.append([regex, size, match_count, exec_time, note])

with open(summary_path, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["正規表現", "文字数", "マッチ行数", "実行時間(秒)", "備考"])
    writer.writerows(rows)

print(f"[Summary] {len(rows)} rows -> {summary_path}")
PYEOF

echo ""
echo "=================================================="
echo " GPU Sweep complete!"
echo " Raw CSVs : $SWEEP_DIR/"
echo " Summary  : $SUMMARY"
echo "=================================================="
echo ""
echo "--- Preview (first 20 rows) ---"
head -21 "$SUMMARY"
echo ""
echo "--- グラフ生成 ---"
echo "python3 scripts/plot_benchmark.py \\"
echo "    --cpu results/sweep_<CPU_TIMESTAMP>.csv \\"
echo "    --gpu $SUMMARY"
