#!/bin/bash
set -e

cp ./data/test_cases.csv ./data/test_cases.csv.bak
cleanup() {
    cp ./data/test_cases.csv.bak ./data/test_cases.csv
    rm -f ./data/test_cases.csv.bak
}
trap cleanup EXIT

echo "正規表現" > ./data/test_cases.csv
cat ./sprints/003/patterns_exp003.txt >> ./data/test_cases.csv

ls ./results/results_*.csv 2>/dev/null | sort > /tmp/asan_before.txt
./run_exp003_cpu_asan.out ./data/wiki_plain.txt 95909488
ls ./results/results_*.csv 2>/dev/null | sort > /tmp/asan_after.txt

NEW_CSV=$(comm -13 /tmp/asan_before.txt /tmp/asan_after.txt | head -1)
if [ -n "$NEW_CSV" ] && [ -f "$NEW_CSV" ]; then
    cp "$NEW_CSV" ./results/sprint003_exp/cpu_asan/run_1.csv
    echo "Successfully updated ./results/sprint003_exp/cpu_asan/run_1.csv"
fi
