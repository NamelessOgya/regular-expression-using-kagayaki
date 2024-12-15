source /etc/profile.d/modules.csh
module load singularity
mkdir -p ./tmp
chmod 755 ./tmp

echo "==== dive into container ====="
singularity shell --nv --bind ./tmp:/container/tmp ./singularity/re_exp_env.sif 


