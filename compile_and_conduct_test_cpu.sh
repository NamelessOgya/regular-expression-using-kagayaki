#!/usr/bin/env bash
set -e

INC="-I./include"

# 1) ライブラリ部をオブジェクト化（main を無効化済みなら安全）
gcc $INC -Wall -Wextra -c sandbox/nfa.c -o nfa.o

# 2) テストプログラムをオブジェクト化
gcc $INC -Wall -Wextra -c src/test_nfa.c -o test_nfa.o

# 3) 両オブジェクトをリンクして実行ファイルを生成
gcc -o test_nfa.out nfa.o test_nfa.o

# 4) 実行権を付与＆起動
chmod +x test_nfa.out
./test_nfa.out
