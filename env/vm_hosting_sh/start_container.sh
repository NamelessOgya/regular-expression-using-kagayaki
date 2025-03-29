docker run -it --gpus all --name reg -v "$(pwd):/app" namelessogya/re_exp_env:cpu 
docker exec -it reg bash