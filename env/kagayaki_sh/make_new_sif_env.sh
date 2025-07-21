#!/bin/csh
csh << EOF
source /etc/profile.d/modules.csh
module load singularity
mkdir singularity
singularity pull ./singularity/re_exp_env.sif docker://namelessogya/re_exp_env:latest
EOF