#!/usr/bin/env bash

# Run from the k8s-gateway VM.
# This verifies Kubernetes prerequisites on every worker node.

set -u

WORKER_NODES=(
    "10.0.1.11"
    "10.0.1.12"
    "10.0.1.13"
)

REMOTE_USER="azureuser"
FAILED_NODES=()

for node in "${WORKER_NODES[@]}"; do
    echo
    echo "========================================"
    echo "Validating ${node}"
    echo "========================================"

    if ssh \
        -o StrictHostKeyChecking=accept-new \
        "${REMOTE_USER}@${node}" '
            VALIDATION_FAILED=0

            echo -n "Hostname: "
            hostname

            echo -n "containerd status: "
            if sudo systemctl is-active --quiet containerd; then
                echo "active"
            else
                echo "inactive - ERROR"
                VALIDATION_FAILED=1
            fi

            echo -n "containerd enabled: "
            if sudo systemctl is-enabled --quiet containerd; then
                echo "enabled"
            else
                echo "not enabled - ERROR"
                VALIDATION_FAILED=1
            fi

            echo -n "kubelet enabled: "
            if sudo systemctl is-enabled --quiet kubelet; then
                echo "enabled"
            else
                echo "not enabled - ERROR"
                VALIDATION_FAILED=1
            fi

            echo -n "Swap: "
            if swapon --show | grep -q .; then
                echo "enabled - ERROR"
                VALIDATION_FAILED=1
            else
                echo "disabled"
            fi

            echo -n "IPv4 forwarding: "
            IP_FORWARD="$(sysctl -n net.ipv4.ip_forward)"

            if [[ "${IP_FORWARD}" == "1" ]]; then
                echo "1"
            else
                echo "${IP_FORWARD} - ERROR"
                VALIDATION_FAILED=1
            fi

            echo -n "overlay module: "
            if lsmod | grep -q "^overlay"; then
                echo "loaded"
            else
                echo "not loaded - ERROR"
                VALIDATION_FAILED=1
            fi

            echo -n "br_netfilter module: "
            if lsmod | grep -q "^br_netfilter"; then
                echo "loaded"
            else
                echo "not loaded - ERROR"
                VALIDATION_FAILED=1
            fi

            echo -n "SystemdCgroup: "
            if sudo grep -q "SystemdCgroup = true" \
                /etc/containerd/config.toml 2>/dev/null; then

                sudo grep -m1 "SystemdCgroup" \
                    /etc/containerd/config.toml
            else
                echo "not configured - ERROR"
                VALIDATION_FAILED=1
            fi

            echo -n "Kubernetes version: "
            if command -v kubeadm >/dev/null 2>&1; then
                kubeadm version -o short
            else
                echo "kubeadm not installed - ERROR"
                VALIDATION_FAILED=1
            fi

            echo -n "Kubelet version: "
            if command -v kubelet >/dev/null 2>&1; then
                kubelet --version
            else
                echo "kubelet not installed - ERROR"
                VALIDATION_FAILED=1
            fi

            echo -n "kubectl client: "
            if command -v kubectl >/dev/null 2>&1; then
                kubectl version --client
            else
                echo "kubectl not installed - ERROR"
                VALIDATION_FAILED=1
            fi

            echo -n "Internet access: "
            if curl -4fsS \
                --connect-timeout 10 \
                https://pkgs.k8s.io/ \
                >/dev/null; then

                echo "working"
            else
                echo "failed - ERROR"
                VALIDATION_FAILED=1
            fi

            exit "${VALIDATION_FAILED}"
        '; then

        echo "RESULT: ${node} passed"
    else
        echo "RESULT: ${node} failed"
        FAILED_NODES+=("${node}")
    fi
done

echo
echo "========================================"
echo "Validation summary"
echo "========================================"

if [[ "${#FAILED_NODES[@]}" -eq 0 ]]; then
    echo "All worker nodes passed validation."
    exit 0
else
    echo "The following worker nodes failed:"
    printf " - %s\n" "${FAILED_NODES[@]}"
    exit 1
fi