#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE_NAME="re_exp_env_gpu"

echo "=== Building GPU environment image: ${IMAGE_NAME} ==="
docker build -t "${IMAGE_NAME}" -f "${SCRIPT_DIR}/Dockerfile.gpu" "${SCRIPT_DIR}"
echo "=== Build completed: ${IMAGE_NAME} ==="