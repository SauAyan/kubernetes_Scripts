#!/usr/bin/env bash
set -Eeuo pipefail

# Azure Kubernetes lab - create 3 private worker nodes
# Run from Azure Cloud Shell (Bash).
#
# Topology:
#   Gateway: 10.0.0.10
#   Manager: 10.0.1.10
#   Node 1:  10.0.1.11
#   Node 2:  10.0.1.12
#   Node 3:  10.0.1.13
#
# The nodes have no public IP and are reachable through the gateway.

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-kubernetes-lab}"
LOCATION="${LOCATION:-centralindia}"
VNET_NAME="${VNET_NAME:-k8s-vnet}"
CLUSTER_SUBNET_NAME="${CLUSTER_SUBNET_NAME:-cluster-subnet}"
CLUSTER_SUBNET_PREFIX="${CLUSTER_SUBNET_PREFIX:-10.0.1.0/24}"
GATEWAY_SUBNET_PREFIX="${GATEWAY_SUBNET_PREFIX:-10.0.0.0/24}"
GATEWAY_PRIVATE_IP="${GATEWAY_PRIVATE_IP:-10.0.0.10}"

ADMIN_USER="${ADMIN_USER:-azureuser}"
VM_SIZE="${VM_SIZE:-Standard_B2s}"          # 2 vCPU, 4 GiB RAM
IMAGE="${IMAGE:-Ubuntu2204}"
OS_DISK_SIZE_GB="${OS_DISK_SIZE_GB:-50}"
STORAGE_SKU="${STORAGE_SKU:-StandardSSD_LRS}"

NSG_NAME="${NSG_NAME:-k8s-nodes-nsg}"
ROUTE_TABLE_NAME="${ROUTE_TABLE_NAME:-k8s-cluster-route-table}"

# Use the public key corresponding to your Windows gateway PEM.
# Upload k8s-gateway-key.pub to Cloud Shell before running.
SSH_PUBLIC_KEY_FILE="${SSH_PUBLIC_KEY_FILE:-$HOME/k8s-gateway-key.pub}"

NODE_NAMES=("k8s-node-1" "k8s-node-2" "k8s-node-3")
NODE_IPS=("10.0.1.11" "10.0.1.12" "10.0.1.13")

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

command -v az >/dev/null 2>&1 || fail "Azure CLI is unavailable."
az account show >/dev/null 2>&1 || fail "Not signed in to Azure."

[[ -f "$SSH_PUBLIC_KEY_FILE" ]] || fail \
"SSH public key not found: $SSH_PUBLIC_KEY_FILE

Upload the public key matching your Windows PEM into Cloud Shell as:
  ~/k8s-gateway-key.pub

Or run with:
  SSH_PUBLIC_KEY_FILE=/path/to/key.pub ./setup_azure_k8s_nodes.sh"

grep -Eq '^ssh-(rsa|ed25519|ecdsa-[^ ]+) ' "$SSH_PUBLIC_KEY_FILE" \
  || fail "'$SSH_PUBLIC_KEY_FILE' does not appear to be a valid OpenSSH public key."

log "Checking existing Azure infrastructure"
az group show -g "$RESOURCE_GROUP" >/dev/null \
  || fail "Resource group '$RESOURCE_GROUP' does not exist."
az network vnet show -g "$RESOURCE_GROUP" -n "$VNET_NAME" >/dev/null \
  || fail "VNet '$VNET_NAME' does not exist."
az network vnet subnet show \
  -g "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  -n "$CLUSTER_SUBNET_NAME" >/dev/null \
  || fail "Subnet '$CLUSTER_SUBNET_NAME' does not exist."

log "Checking that the cluster subnet is associated with the gateway route table"
ASSOCIATED_ROUTE_TABLE=$(az network vnet subnet show \
  -g "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  -n "$CLUSTER_SUBNET_NAME" \
  --query "routeTable.id" -o tsv)

if [[ -z "$ASSOCIATED_ROUTE_TABLE" ]]; then
  fail "The cluster subnet has no route table. Associate '$ROUTE_TABLE_NAME' first."
fi

EXISTING_DEFAULT_ROUTE=$(az network route-table route list \
  -g "$RESOURCE_GROUP" \
  --route-table-name "$ROUTE_TABLE_NAME" \
  --query "[?addressPrefix=='0.0.0.0/0'] | [0].{name:name,nextHop:nextHopType,nextHopIP:nextHopIpAddress}" \
  -o json)

DEFAULT_NEXT_HOP=$(printf '%s' "$EXISTING_DEFAULT_ROUTE" | \
  python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("nextHop",""))')
DEFAULT_NEXT_HOP_IP=$(printf '%s' "$EXISTING_DEFAULT_ROUTE" | \
  python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("nextHopIP",""))')

[[ "$DEFAULT_NEXT_HOP" == "VirtualAppliance" ]] \
  || fail "No valid 0.0.0.0/0 VirtualAppliance route found in '$ROUTE_TABLE_NAME'."
[[ "$DEFAULT_NEXT_HOP_IP" == "$GATEWAY_PRIVATE_IP" ]] \
  || fail "Default route points to '$DEFAULT_NEXT_HOP_IP', expected '$GATEWAY_PRIVATE_IP'."

log "Creating or updating the worker-node NSG"
if ! az network nsg show -g "$RESOURCE_GROUP" -n "$NSG_NAME" >/dev/null 2>&1; then
  az network nsg create \
    -g "$RESOURCE_GROUP" \
    -n "$NSG_NAME" \
    -l "$LOCATION" >/dev/null
fi

# Allow SSH only through the gateway subnet.
az network nsg rule create \
  -g "$RESOURCE_GROUP" \
  --nsg-name "$NSG_NAME" \
  -n AllowSSHFromGateway \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes "$GATEWAY_SUBNET_PREFIX" \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 22 \
  --only-show-errors >/dev/null 2>&1 || \
az network nsg rule update \
  -g "$RESOURCE_GROUP" \
  --nsg-name "$NSG_NAME" \
  -n AllowSSHFromGateway \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes "$GATEWAY_SUBNET_PREFIX" \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 22 >/dev/null

# Permit all manager-to-worker and worker-to-worker traffic.
az network nsg rule create \
  -g "$RESOURCE_GROUP" \
  --nsg-name "$NSG_NAME" \
  -n AllowClusterInternal \
  --priority 110 \
  --direction Inbound \
  --access Allow \
  --protocol '*' \
  --source-address-prefixes "$CLUSTER_SUBNET_PREFIX" \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges '*' \
  --only-show-errors >/dev/null 2>&1 || \
az network nsg rule update \
  -g "$RESOURCE_GROUP" \
  --nsg-name "$NSG_NAME" \
  -n AllowClusterInternal \
  --priority 110 \
  --direction Inbound \
  --access Allow \
  --protocol '*' \
  --source-address-prefixes "$CLUSTER_SUBNET_PREFIX" \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges '*' >/dev/null

for i in "${!NODE_NAMES[@]}"; do
  VM_NAME="${NODE_NAMES[$i]}"
  PRIVATE_IP="${NODE_IPS[$i]}"
  NIC_NAME="${VM_NAME}-nic"

  log "Creating $VM_NAME with private IP $PRIVATE_IP"

  if ! az network nic show -g "$RESOURCE_GROUP" -n "$NIC_NAME" >/dev/null 2>&1; then
    az network nic create \
      -g "$RESOURCE_GROUP" \
      -n "$NIC_NAME" \
      -l "$LOCATION" \
      --vnet-name "$VNET_NAME" \
      --subnet "$CLUSTER_SUBNET_NAME" \
      --network-security-group "$NSG_NAME" \
      --private-ip-address "$PRIVATE_IP" \
      --only-show-errors >/dev/null
  else
    ACTUAL_IP=$(az network nic show \
      -g "$RESOURCE_GROUP" -n "$NIC_NAME" \
      --query "ipConfigurations[0].privateIPAddress" -o tsv)

    [[ "$ACTUAL_IP" == "$PRIVATE_IP" ]] || fail \
      "NIC '$NIC_NAME' already exists with IP '$ACTUAL_IP', expected '$PRIVATE_IP'."
  fi

  if az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" >/dev/null 2>&1; then
    echo "VM '$VM_NAME' already exists; skipping VM creation."
  else
    CLOUD_INIT=$(mktemp)
    cat > "$CLOUD_INIT" <<EOF
#cloud-config
package_update: true
packages:
  - openssh-server
runcmd:
  - systemctl enable --now ssh
  - hostnamectl set-hostname ${VM_NAME}
EOF

    az vm create \
      -g "$RESOURCE_GROUP" \
      -n "$VM_NAME" \
      -l "$LOCATION" \
      --nics "$NIC_NAME" \
      --image "$IMAGE" \
      --size "$VM_SIZE" \
      --admin-username "$ADMIN_USER" \
      --ssh-key-values "$SSH_PUBLIC_KEY_FILE" \
      --os-disk-size-gb "$OS_DISK_SIZE_GB" \
      --storage-sku "$STORAGE_SKU" \
      --custom-data "$CLOUD_INIT" \
      --only-show-errors >/dev/null

    rm -f "$CLOUD_INIT"
  fi

  az vm wait -g "$RESOURCE_GROUP" -n "$VM_NAME" --created
done

log "Worker-node deployment summary"
printf '%-16s %-13s %-18s %-10s\n' "VM" "PRIVATE IP" "SIZE" "PUBLIC IP"
printf '%-16s %-13s %-18s %-10s\n' "----------------" "-------------" "------------------" "----------"

for i in "${!NODE_NAMES[@]}"; do
  VM_NAME="${NODE_NAMES[$i]}"
  NIC_NAME="${VM_NAME}-nic"

  PRIVATE_IP=$(az network nic show \
    -g "$RESOURCE_GROUP" -n "$NIC_NAME" \
    --query "ipConfigurations[0].privateIPAddress" -o tsv)

  PUBLIC_IP=$(az vm show \
    -g "$RESOURCE_GROUP" -n "$VM_NAME" -d \
    --query "publicIps" -o tsv)

  printf '%-16s %-13s %-18s %-10s\n' \
    "$VM_NAME" "$PRIVATE_IP" "$VM_SIZE" "${PUBLIC_IP:-None}"
done

cat <<EOF

The three worker VMs are ready.

From Windows, connect to the gateway with agent forwarding:

  ssh -A -i "C:\Users\Ayan\Downloads\Kubernetes\Azure_setup\Azure_ssh_keys\k8s-gateway-key.pem" azureuser@<GATEWAY_PUBLIC_IP>

From the gateway, test each node:

  ssh $ADMIN_USER@10.0.1.11
  ssh $ADMIN_USER@10.0.1.12
  ssh $ADMIN_USER@10.0.1.13

On each node, verify:

  hostname
  hostname -I
  curl -s https://api.ipify.org ; echo
  sudo apt update

Expected hostnames:
  k8s-node-1
  k8s-node-2
  k8s-node-3

All nodes:
  - have no public IP
  - use 2 vCPU and 4 GiB RAM by default
  - have a 50 GiB Standard SSD OS disk
  - route outbound traffic through gateway $GATEWAY_PRIVATE_IP
EOF
