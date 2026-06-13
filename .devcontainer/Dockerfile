FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    tzdata \
    wget \
    g++ \
    cmake \
    git \
    clang-format \
    python3 \
    python3-pip \
    locales \
    && rm -rf /var/lib/apt/lists/*

ENV TZ=Asia/Tokyo

# locale 設定（たまに datasets で必要になる）
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# python / pip が存在しない場合のみリンクを作成
RUN [ ! -e /usr/bin/python ] && ln -s /usr/bin/python3 /usr/bin/python || true \
 && [ ! -e /usr/bin/pip ] && ln -s /usr/bin/pip3 /usr/bin/pip || true

# Hugging Face 関連ライブラリをインストール
RUN pip install --no-cache-dir \
    datasets \
    transformers \
    numpy \
    pandas \
    tqdm
