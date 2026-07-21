#!/usr/bin/env bash

# Run from the k8s-gateway VM.
# This installs Kubernetes prerequisites on all worker nodes sequentially.

set -Eeuo pipefail

WORKER_NODES=(
    "10.0.1.11"
    "10.0.1.12"
    "10.0.1.13"
)

SETUP_SCRIPT="/home/azureuser/kubernetes_setup.sh"
REMOTE_USER="azureuser"
REMOTE_SCRIPT="/home/azureuser/kubernetes_setup.sh"

if [[ ! -f "${SETUP_SCRIPT}" ]]; then
    echo "ERROR: Setup script not found:"
    echo "${SETUP_SCRIPT}"
    exit 1
fi

for node in "${WORKER_NODES[@]}"; do
    echo
    echo "========================================"
    echo "Installing Kubernetes on ${node}"
    echo "========================================"

    echo "Copying setup script..."

    scp \
        -o StrictHostKeyChecking=accept-new \
        "${SETUP_SCRIPT}" \
        "${REMOTE_USER}@${node}:${REMOTE_SCRIPT}"

    echo "Running setup script..."

    if ssh \
        -t \
        -o StrictHostKeyChecking=accept-new \
        "${REMOTE_USER}@${node}" \
        "chmod +x '${REMOTE_SCRIPT}' && sudo '${REMOTE_SCRIPT}'"; then

        echo
        echo "SUCCESS: Installation completed on ${node}"
    else
        echo
        echo "ERROR: Installation failed on ${node}"
        echo "The remaining nodes were not processed."
        exit 1
    fi
done

echo
echo "========================================"
echo "All worker installations completed"
echo "========================================"