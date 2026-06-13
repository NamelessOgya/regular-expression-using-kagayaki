#!/bin/bash
docker run --rm -it --gpus all -v "$(pwd)":/app re_exp_env_gpu bash