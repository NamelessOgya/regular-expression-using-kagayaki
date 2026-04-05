#!/bin/bash
# カレントディレクトリを /app にマウントし、ビルドした環境を起動する
docker run --rm -it --gpus all -v "$(pwd)":/app kagayaki-nfa-env bash