#!/bin/bash

if [ -f cluster.env ]; then
  set -a
  source cluster.env
  set +a
else
  echo "Warning: cluster.env not found. Copy cluster.env.example to cluster.env."
  echo "Using defaults: m5.xlarge, 2 core nodes."
fi

export TF_VAR_core_instance_type="${CLUSTER_INSTANCE_TYPE:-m5.xlarge}"
export TF_VAR_core_count="${CLUSTER_CORE_COUNT:-2}"

echo "Deploying with: ${TF_VAR_core_instance_type} x${TF_VAR_core_count} core nodes"
echo ""

terraform "$@"
