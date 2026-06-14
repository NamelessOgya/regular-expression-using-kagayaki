#!/usr/bin/env python3
"""
aggregate.py - sweep の生CSVディレクトリからサマリーCSVを作る補助スクリプト
使い方: python3 /tmp/aggregate.py <manifest.txt> <output.csv>
"""
import csv, os, sys

csv.field_size_limit(sys.maxsize)

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
            next(reader)
            for row in reader:
                if len(row) < 5:
                    continue
                regex       = row[0].strip().rstrip("\n\r")
                match_count = row[2].strip()
                exec_time   = row[4].strip()
                
                # Check for 7 columns (new format)
                if len(row) >= 7:
                    cpu_pre_time = row[5].strip()
                    gpu_exec_time = row[6].strip()
                else:
                    # Fallback for old format (cpu_pre_time = 0.0, gpu_exec_time = exec_time)
                    cpu_pre_time = "0.000000"
                    gpu_exec_time = exec_time
                
                note = "TIMEOUT" if exec_time == "300.000000" else ""
                rows.append([regex, size, match_count, exec_time, cpu_pre_time, gpu_exec_time, note])

with open(summary_path, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["正規表現", "文字数", "マッチ行数", "実行時間(秒)", "CPU前処理(秒)", "GPU実行(秒)", "備考"])
    writer.writerows(rows)

print(f"[Summary] {len(rows)} rows -> {summary_path}")
