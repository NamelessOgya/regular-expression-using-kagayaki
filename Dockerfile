# ベースとなるOSは CUDA 環境入りの Ubuntu を選択
FROM nvidia/cuda:11.8.0-devel-ubuntu22.04

# パッケージの一覧更新
RUN apt-get update

# タイムゾーンの設定
ENV TZ=Asia/Tokyo
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 開発環境のシステムインストール
RUN apt install -y wget \
  g++ \
  cmake \
  git \
  clang-format

# Taskランナーのインストール
RUN sh -c "$(wget -qO- https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

# ログイン時やコマンド実行時に自動で /app ディレクトリに移動する
WORKDIR /app