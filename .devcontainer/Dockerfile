# .devcontainer/Dockerfile
FROM ubuntu:20.04

# 非対話モード設定とパッケージ更新
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    tzdata \
    wget \
    g++ \
    cmake \
    git \
    clang-format \
 && rm -rf /var/lib/apt/lists/*

ENV TZ=Asia/Tokyo
