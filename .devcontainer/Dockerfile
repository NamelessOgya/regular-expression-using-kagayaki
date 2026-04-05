# .devcontainer/Dockerfile
FROM ubuntu:20.04

# 非対話モード設定とパッケージ更新
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Tokyo

RUN apt-get update && apt-get install -y \
    tzdata \
    wget \
    g++ \
    cmake \
    git \
    clang-format \
 && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
 && rm -rf /var/lib/apt/lists/*

# Taskランナーのインストール
RUN sh -c "$(wget -qO- https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

# ログイン時に自動で /app ディレクトリを開く
WORKDIR /app
