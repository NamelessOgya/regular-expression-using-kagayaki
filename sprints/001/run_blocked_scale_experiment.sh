#!/usr/bin/env bash
# =============================================================
# run_blocked_scale_experiment.sh
# blocked-small / blocked-medium / blocked-large の3データセットで
# GPU Line / Chunk Static / Chunk Dynamic を N_RUNS 回計測して avg.csv を生成する。
#
# nvcc なしで実行可能（既存の .out ファイルを使用）。
# =============================================================
set -e

N_RUNS=3
OUT_BASE="results/sprint001_blocked_scale"

while [[ $# -gt 0 ]]; do
    case $1 in
        --runs) N_RUNS="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

BINARY_LINE="./run_benchmark_gpu_line.out"
BINARY_CHUNK="./run_benchmark_gpu_chunk.out"
BINARY_DYN="./run_benchmark_gpu_chunk_dynamic.out"

for b in "$BINARY_LINE" "$BINARY_CHUNK" "$BINARY_DYN"; do
    if [ ! -x "$b" ]; then
        echo "[ERROR] Executable not found: $b"; exit 1
    fi
done

declare -a NAMES=("blocked-small"  "blocked-medium"  "blocked-large")
declare -a FILES=("data/experiment/blocked-small.txt"
                  "data/experiment/blocked-medium.txt"
                  "data/experiment/blocked-large.txt")
declare -a SIZES=(5276414 10298334 26166954)

mkdir -p "$OUT_BASE"

echo "=============================================================="
echo " run_blocked_scale_experiment.sh"
echo " Runs : $N_RUNS"
echo " Out  : $OUT_BASE"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================================="

for idx in 0 1 2; do
    NAME="${NAMES[$idx]}"
    FILE="${FILES[$idx]}"
    SIZE="${SIZES[$idx]}"

    if [ ! -f "$FILE" ]; then
        echo "[ERROR] Data file not found: $FILE"; exit 1
    fi

    echo ""
    echo "=============================="
    echo " Dataset: $NAME  ($SIZE bytes)"
    echo "=============================="

    DIR_LINE="$OUT_BASE/${NAME}/gpu_line"
    DIR_CHUNK="$OUT_BASE/${NAME}/gpu_chunk"
    DIR_DYN="$OUT_BASE/${NAME}/gpu_chunk_dynamic"
    mkdir -p "$DIR_LINE" "$DIR_CHUNK" "$DIR_DYN"

    # --- GPU Line ---
    echo ""
    echo "--- [GPU Line] $N_RUNS runs ---"
    LINE_CSVS=()
    for i in $(seq 1 "$N_RUNS"); do
        echo "  Run $i / $N_RUNS ..."
        rm -f ./results/results_*.csv
        "$BINARY_LINE" "$FILE" "$SIZE" || true
        CSV=$(ls -t ./results/results_*.csv 2>/dev/null | head -1 || true)
        if [ -n "$CSV" ]; then
            DEST="$DIR_LINE/run${i}.csv"
            cp "$CSV" "$DEST"
            LINE_CSVS+=("$DEST")
        fi
    done
    python3 scripts/average_raw_runs.py "$SIZE" "${LINE_CSVS[@]}" "$DIR_LINE/avg.csv"
    echo "  -> $DIR_LINE/avg.csv"

    # --- GPU Chunk Static ---
    echo ""
    echo "--- [GPU Chunk Static] $N_RUNS runs ---"
    CHUNK_CSVS=()
    for i in $(seq 1 "$N_RUNS"); do
        echo "  Run $i / $N_RUNS ..."
        rm -f ./results/results_*.csv
        "$BINARY_CHUNK" "$FILE" "$SIZE" || true
        CSV=$(ls -t ./results/results_*.csv 2>/dev/null | head -1 || true)
        if [ -n "$CSV" ]; then
            DEST="$DIR_CHUNK/run${i}.csv"
            cp "$CSV" "$DEST"
            CHUNK_CSVS+=("$DEST")
        fi
    done
    python3 scripts/average_raw_runs.py "$SIZE" "${CHUNK_CSVS[@]}" "$DIR_CHUNK/avg.csv"
    echo "  -> $DIR_CHUNK/avg.csv"

    # --- GPU Chunk Dynamic ---
    echo ""
    echo "--- [GPU Chunk Dynamic] $N_RUNS runs ---"
    DYN_CSVS=()
    for i in $(seq 1 "$N_RUNS"); do
        echo "  Run $i / $N_RUNS ..."
        rm -f ./results/results_*.csv
        "$BINARY_DYN" "$FILE" "$SIZE" || true
        CSV=$(ls -t ./results/results_*.csv 2>/dev/null | head -1 || true)
        if [ -n "$CSV" ]; then
            DEST="$DIR_DYN/run${i}.csv"
            cp "$CSV" "$DEST"
            DYN_CSVS+=("$DEST")
        fi
    done
    python3 scripts/average_raw_runs.py "$SIZE" "${DYN_CSVS[@]}" "$DIR_DYN/avg.csv"
    echo "  -> $DIR_DYN/avg.csv"

done

echo ""
echo "=============================================================="
echo " 全データセット完了。結果: $OUT_BASE/"
echo "=============================================================="
