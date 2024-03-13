#!/bin/bash

source /etc/profile.d/julia.sh
source /etc/profile.d/conda.sh
conda activate root
/anaconda/bin/jupyterhub --log-file=/var/log/jupyterhub.log -f /etc/jupyterhub/jupyterhub_config.py