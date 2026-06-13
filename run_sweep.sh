#!/usr/bin/env bash
# =============================================================
# run_sweep.sh
# 正規表現 × テキスト文字数のグリッドでベンチマークを実行し、
# 結果を results/sweep_<timestamp>.csv にまとめる。
#
# 使い方:
#   ./run_sweep.sh                              # 全サイズ自動 (100→...→MAX)
#   ./run_sweep.sh ./data/wiki_plain.txt        # ファイル指定
#   ./run_sweep.sh ./data/wiki_plain.txt 100 1000 10000  # サイズ手動指定
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

# UTF-8 文字数を正確に取得（wc -c はバイト数なので Python で計算）
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
TIMESTAMP=$(date +%Y%m%d_%H_%M_%S)
SWEEP_DIR="./results/sweep_${TIMESTAMP}"   # 各サイズの生CSVをここに置く
SUMMARY="./results/sweep_${TIMESTAMP}.csv"
mkdir -p "$SWEEP_DIR"

echo "=================================================="
echo " Benchmark Sweep"
echo " Target : $WIKI_FILE  (~${MAX_CHARS} bytes)"
echo " Sizes  : ${SIZES[*]}"
echo " Summary: $SUMMARY"
echo "=================================================="

# --------------------------------------------------------
# ビルド
# --------------------------------------------------------
echo ""
echo "[Build] Compiling benchmark binary..."
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
# サイズごとに実行（結果を SWEEP_DIR に移動して管理）
# --------------------------------------------------------
# "raw_csvパス:文字数" を1行ずつ記録するファイル
MANIFEST="${SWEEP_DIR}/manifest.txt"

for size in "${SIZES[@]}"; do
    echo ""
    echo "----------------------------------------------"
    echo " [RUN] size = ${size} chars"
    echo "----------------------------------------------"

    # run_benchmark.asan は ./results/results_<timestamp>.csv を生成する
    # 実行直前・直後のファイルを比較するのではなく、
    # 出力先を SWEEP_DIR に向けるためシンボリックリンクを一時的に差し替える。
    # →より確実: RESULTS 環境変数は使えないため、実行後に最新ファイルを mv する。

    # 実行前のファイル一覧を記録
    ls ./results/results_*.csv 2>/dev/null | sort > /tmp/sweep_before.txt || true

    "$BINARY" "$WIKI_FILE" "$size"

    # 実行後に新しく増えたファイルを特定
    ls ./results/results_*.csv 2>/dev/null | sort > /tmp/sweep_after.txt || true
    NEW_FILE=$(comm -13 /tmp/sweep_before.txt /tmp/sweep_after.txt | head -1 || true)

    if [ -z "$NEW_FILE" ]; then
        # 同秒内に複数実行された場合: 最新を使う（重複可能性あり）
        NEW_FILE=$(ls -t ./results/results_*.csv 2>/dev/null | head -1 || true)
        echo "[WARN] Could not detect new file by diff; using latest: $NEW_FILE"
    fi

    if [ -n "$NEW_FILE" ]; then
        # SWEEP_DIR にサイズ付きの名前でコピー
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
echo " Sweep complete!"
echo " Raw CSVs : $SWEEP_DIR/"
echo " Summary  : $SUMMARY"
echo "=================================================="
echo ""
echo "--- Preview (first 30 rows) ---"
head -31 "$SUMMARY"
