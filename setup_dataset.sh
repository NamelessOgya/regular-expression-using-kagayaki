#!/bin/bash
set -e

# ディレクトリ定義
DATA_DIR="./data"
SCRIPTS_DIR="./scripts"
TEMP_DIR="./temp_dataset"

echo "=== Starting Wikipedia Dataset Setup ==="

# 必要なディレクトリの作成
mkdir -p "$DATA_DIR"
mkdir -p "$SCRIPTS_DIR"
mkdir -p "$TEMP_DIR"

ZIP_FILE="$TEMP_DIR/enwik8.zip"
UNZIPPED_FILE="$TEMP_DIR/enwik8"
WIKI_PLAIN="$DATA_DIR/wiki_plain.txt"

if [ ! -f "$WIKI_PLAIN" ]; then
    if [ ! -f "$UNZIPPED_FILE" ]; then
        if [ ! -f "$ZIP_FILE" ]; then
            echo "Downloading enwik8.zip (approx. 36MB)..."
            curl -sS -o "$ZIP_FILE" "http://mattmahoney.net/dc/enwik8.zip"
        else
            echo "enwik8.zip already exists. Skipping download."
        fi

        echo "Unzipping enwik8.zip using Python..."
        python3 -c "import zipfile; zipfile.ZipFile('$ZIP_FILE').extractall('$TEMP_DIR')"
    else
        echo "enwik8 already unzipped. Skipping unzip."
    fi

    echo "Converting enwik8 to plain text (stripping XML)..."
    python3 "$SCRIPTS_DIR/clean_wiki.py" "$UNZIPPED_FILE" "$WIKI_PLAIN"
else
    echo "wiki_plain.txt already exists. Skipping conversion."
fi

# 一時ファイルの削除
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

echo "=== Wikipedia Dataset Setup Completed Successfully! ==="
echo "Clean plain text saved to: $WIKI_PLAIN"
ls -lh "$WIKI_PLAIN"
