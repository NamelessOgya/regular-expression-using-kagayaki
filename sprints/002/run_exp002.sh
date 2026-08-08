#!/bin/bash
# =============================================================
# sprints/002/run_exp002.sh
# NFA 状態数 |Q| 要因分離実験 (Sprint 002) 実行スクリプト
# =============================================================
set -e

WIKI_FILE="./data/wiki_plain.txt"
PATTERNS_FILE="./sprints/002/patterns.txt"
OUT_DIR="./results/sprint002_exp"
N_RUNS=3

echo "=============================================="
echo " Sprint 002: NFA 状態数 |Q| 要因分離実験"
echo " データセット: $WIKI_FILE"
echo " 試行回数    : $N_RUNS 回"
echo "=============================================="

# 1. test_cases.csv の安全な差し替え
cp ./data/test_cases.csv ./data/test_cases.csv.bak
cleanup() {
    cp ./data/test_cases.csv.bak ./data/test_cases.csv
    rm -f ./data/test_cases.csv.bak
}
trap cleanup EXIT

echo "正規表現" > ./data/test_cases.csv
cat "$PATTERNS_FILE" >> ./data/test_cases.csv

# 2. LPC=1 (GPU Line構造) と LPC=8 (Chunked-Static) の計測実行
mkdir -p "$OUT_DIR"

echo "[1/1] 状態数 |Q| スケーリング計測 (LPC=1 vs LPC=8)..."
bash run_lpc_sweep.sh "$WIKI_FILE" --out "$OUT_DIR" --runs "$N_RUNS" --lpc 1 8

echo "=============================================="
echo " Sprint 002 実験計測完了!"
echo " 結果: $OUT_DIR"
echo "=============================================="
