#!/usr/bin/env bash
# =============================================================
# sprints/003/run_scale_exp003.sh
# Sprint 003: 被検索テキスト文字数スケール実験スクリプト
# =============================================================
set -e

WIKI_FILE="./data/wiki_plain.txt"
PATTERNS_FILE="./sprints/003/patterns_exp003.txt"
OUT_BASE="./results/sprint003_scale"
N_RUNS=3

# スイープ対象文字数 (10K, 100K, 1M, 10M, 95.9M)
SCALE_SIZES=(10000 100000 1000000 10000000 95909488)

mkdir -p "$OUT_BASE"

# test_cases.csv の安全な差し替え
cp ./data/test_cases.csv ./data/test_cases.csv.bak
cleanup() {
    cp ./data/test_cases.csv.bak ./data/test_cases.csv
    rm -f ./data/test_cases.csv.bak
}
trap cleanup EXIT

echo "正規表現" > ./data/test_cases.csv
cat "$PATTERNS_FILE" >> ./data/test_cases.csv

echo "=================================================="
echo " Sprint 003: 文字数スケーリング実験"
echo " 対象文字数: ${SCALE_SIZES[*]}"
echo " 試行回数  : $N_RUNS 回"
echo " 出力先    : $OUT_BASE"
echo "=================================================="

# 計測対象バイナリ
declare -A BINS=(
    ["cpu_o3"]="./run_exp003_cpu_o3.out"
    ["gpu_line"]="./run_exp003_gpu_line.out"
    ["gpu_chunk_static"]="./run_exp003_gpu_chunk.out"
    ["gpu_chunk_dynamic"]="./run_exp003_gpu_dynamic.out"
)

for size in "${SCALE_SIZES[@]}"; do
    echo ""
    echo "##################################################"
    echo "  スケール: $size 文字"
    echo "##################################################"
    
    SIZE_DIR="$OUT_BASE/size_${size}"
    mkdir -p "$SIZE_DIR"
    
    # 95909488 文字の場合は sprint003_exp の既存データをコピーして再利用
    if [ "$size" -eq 95909488 ] && [ -d "./results/sprint003_exp" ]; then
        echo "  [Reuse] 95.9M 文字は既存データを再利用します..."
        for strat in cpu_o3 gpu_line gpu_chunk_static gpu_chunk_dynamic; do
            mkdir -p "$SIZE_DIR/$strat"
            cp -r ./results/sprint003_exp/$strat/* "$SIZE_DIR/$strat/" 2>/dev/null || true
        done
        continue
    fi
    
    for strat in cpu_o3 gpu_line gpu_chunk_static gpu_chunk_dynamic; do
        bin="${BINS[$strat]}"
        target_dir="$SIZE_DIR/$strat"
        mkdir -p "$target_dir"
        
        echo "  --- 手法: $strat ($bin, $size chars) ---"
        for run_i in $(seq 1 "$N_RUNS"); do
            out_file="$target_dir/run_${run_i}.csv"
            if [ -f "$out_file" ] && [ -s "$out_file" ]; then
                echo "    Run $run_i: すでに存在するためスキップ"
                continue
            fi
            
            ls ./results/results_*.csv 2>/dev/null | sort > /tmp/scale_before.txt || true
            "$bin" "$WIKI_FILE" "$size" 2>/dev/null || true
            ls ./results/results_*.csv 2>/dev/null | sort > /tmp/scale_after.txt || true
            
            NEW_FILE=$(comm -13 /tmp/scale_before.txt /tmp/scale_after.txt | head -1 || true)
            if [ -n "$NEW_FILE" ] && [ -f "$NEW_FILE" ]; then
                mv "$NEW_FILE" "$out_file"
                echo "    Run $run_i -> $out_file"
            else
                echo "    [WARN] 出力 CSV が見つかりませんでした。"
            fi
        done
    done
done

echo ""
echo "=================================================="
echo " 計測完了! 集計・理論突合スクリプトを実行します..."
echo "=================================================="
python3 sprints/003/analyze_scale_exp003.py
