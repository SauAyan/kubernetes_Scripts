#!/usr/bin/env bash
set -Eeuo pipefail

# Azure Kubernetes lab - Manager VM setup
# Run from Azure Cloud Shell (Bash).
# Creates one private Ubuntu VM in the cluster subnet and routes outbound traffic
# through the existing gateway VM at 10.0.0.10.

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-kubernetes-lab}"
LOCATION="${LOCATION:-centralindia}"
VNET_NAME="${VNET_NAME:-k8s-vnet}"
CLUSTER_SUBNET_NAME="${CLUSTER_SUBNET_NAME:-cluster-subnet}"
CLUSTER_SUBNET_PREFIX="${CLUSTER_SUBNET_PREFIX:-10.0.1.0/24}"
GATEWAY_PRIVATE_IP="${GATEWAY_PRIVATE_IP:-10.0.0.10}"

VM_NAME="${VM_NAME:-k8s-manager}"
NIC_NAME="${NIC_NAME:-k8s-manager-nic}"
NSG_NAME="${NSG_NAME:-k8s-manager-nsg}"
PRIVATE_IP="${PRIVATE_IP:-10.0.1.10}"
ADMIN_USER="${ADMIN_USER:-azureuser}"
VM_SIZE="${VM_SIZE:-Standard_B2s}"       # 2 vCPU, 4 GiB
IMAGE="${IMAGE:-Ubuntu2204}"
OS_DISK_SIZE_GB="${OS_DISK_SIZE_GB:-50}"
ROUTE_TABLE_NAME="${ROUTE_TABLE_NAME:-k8s-cluster-route-table}"
ROUTE_NAME="${ROUTE_NAME:-default-via-gateway}"
SSH_PUBLIC_KEY_FILE="${SSH_PUBLIC_KEY_FILE:-$HOME/.ssh/id_rsa.pub}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

command -v az >/dev/null 2>&1 || fail "Azure CLI (az) is not installed."
az account show >/dev/null 2>&1 || fail "Not signed in to Azure. Run: az login"

if [[ ! -f "$SSH_PUBLIC_KEY_FILE" ]]; then
  log "No SSH key found at $SSH_PUBLIC_KEY_FILE; generating one in Cloud Shell"
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t rsa -b 4096 -f "${SSH_PUBLIC_KEY_FILE%.pub}" -N ""
fi

log "Checking resource group and virtual network"
az group show --name "$RESOURCE_GROUP" >/dev/null \
  || fail "Resource group '$RESOURCE_GROUP' does not exist. Create the gateway first."
az network vnet show -g "$RESOURCE_GROUP" -n "$VNET_NAME" >/dev/null \
  || fail "VNet '$VNET_NAME' does not exist. Create the gateway network first."

log "Ensuring cluster subnet exists"
if ! az network vnet subnet show -g "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" -n "$CLUSTER_SUBNET_NAME" >/dev/null 2>&1; then
  az network vnet subnet create \
    -g "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    -n "$CLUSTER_SUBNET_NAME" \
    --address-prefixes "$CLUSTER_SUBNET_PREFIX" \
    >/dev/null
fi

log "Ensuring route table sends cluster outbound traffic through the gateway"
if ! az network route-table show -g "$RESOURCE_GROUP" -n "$ROUTE_TABLE_NAME" >/dev/null 2>&1; then
  az network route-table create \
    -g "$RESOURCE_GROUP" \
    -n "$ROUTE_TABLE_NAME" \
    -l "$LOCATION" \
    >/dev/null
fi

if ! az network route-table route show \
    -g "$RESOURCE_GROUP" \
    --route-table-name "$ROUTE_TABLE_NAME" \
    -n "$ROUTE_NAME" >/dev/null 2>&1; then
    EXISTING_DEFAULT_ROUTE=$(az network route-table route list \
    --resource-group "$RESOURCE_GROUP" \
    --route-table-name "$ROUTE_TABLE_NAME" \
    --query "[?addressPrefix=='0.0.0.0/0'].name | [0]" \
    --output tsv)

  if [[ -n "$EXISTING_DEFAULT_ROUTE" ]]; then
      echo "Default route already exists: $EXISTING_DEFAULT_ROUTE"

      az network route-table route update \
        --resource-group "$RESOURCE_GROUP" \
        --route-table-name "$ROUTE_TABLE_NAME" \
        --name "$EXISTING_DEFAULT_ROUTE" \
        --next-hop-type VirtualAppliance \
        --next-hop-ip-address 10.0.0.10
  else
      az network route-table route create \
        --resource-group "$RESOURCE_GROUP" \
        --route-table-name "$ROUTE_TABLE_NAME" \
        --name default-via-k8s-gateway \
        --address-prefix 0.0.0.0/0 \
        --next-hop-type VirtualAppliance \
        --next-hop-ip-address 10.0.0.10
  fi
else
  az network route-table route update \
    -g "$RESOURCE_GROUP" \
    --route-table-name "$ROUTE_TABLE_NAME" \
    -n "$ROUTE_NAME" \
    --address-prefix 0.0.0.0/0 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address "$GATEWAY_PRIVATE_IP" \
    >/dev/null
fi

az network vnet subnet update \
  -g "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  -n "$CLUSTER_SUBNET_NAME" \
  --route-table "$ROUTE_TABLE_NAME" \
  >/dev/null

log "Creating manager NSG"
if ! az network nsg show -g "$RESOURCE_GROUP" -n "$NSG_NAME" >/dev/null 2>&1; then
  az network nsg create -g "$RESOURCE_GROUP" -n "$NSG_NAME" -l "$LOCATION" >/dev/null
fi

# SSH is permitted only from the gateway subnet. Azure NSGs are stateful.
if ! az network nsg rule show -g "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" -n AllowSSHFromGateway >/dev/null 2>&1; then
  az network nsg rule create \
    -g "$RESOURCE_GROUP" \
    --nsg-name "$NSG_NAME" \
    -n AllowSSHFromGateway \
    --priority 100 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes 10.0.0.0/24 \
    --source-port-ranges '*' \
    --destination-address-prefixes '*' \
    --destination-port-ranges 22 \
    >/dev/null
fi

# Permit all traffic between cluster machines for later Kubernetes setup.
if ! az network nsg rule show -g "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" -n AllowClusterInternal >/dev/null 2>&1; then
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
    >/dev/null
fi

log "Creating manager NIC with static private IP $PRIVATE_IP and no public IP"
if ! az network nic show -g "$RESOURCE_GROUP" -n "$NIC_NAME" >/dev/null 2>&1; then
  az network nic create \
    -g "$RESOURCE_GROUP" \
    -n "$NIC_NAME" \
    -l "$LOCATION" \
    --vnet-name "$VNET_NAME" \
    --subnet "$CLUSTER_SUBNET_NAME" \
    --network-security-group "$NSG_NAME" \
    --private-ip-address "$PRIVATE_IP" \
    >/dev/null
fi

log "Creating Ubuntu manager VM"
if az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" >/dev/null 2>&1; then
  echo "VM '$VM_NAME' already exists; skipping creation."
else
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
    --storage-sku StandardSSD_LRS \
    --public-ip-address "" \
    --custom-data <(cat <<'CLOUDINIT'
#cloud-config
package_update: true
packages:
  - openssh-server
runcmd:
  - systemctl enable --now ssh
  - hostnamectl set-hostname k8s-manager
CLOUDINIT
) \
    >/dev/null
fi

log "Waiting for VM provisioning"
az vm wait -g "$RESOURCE_GROUP" -n "$VM_NAME" --created

ACTUAL_IP=$(az network nic show -g "$RESOURCE_GROUP" -n "$NIC_NAME" --query 'ipConfigurations[0].privateIPAddress' -o tsv)
PUBLIC_IP=$(az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" -d --query publicIps -o tsv)

cat <<SUMMARY

Manager VM created successfully.

  VM name:        $VM_NAME
  Hostname:       k8s-manager
  Size:           $VM_SIZE
  RAM target:     4 GiB
  OS disk:        ${OS_DISK_SIZE_GB} GiB Standard SSD
  Private IP:     $ACTUAL_IP
  Public IP:      ${PUBLIC_IP:-None}
  Cluster subnet: $CLUSTER_SUBNET_PREFIX
  Gateway:        $GATEWAY_PRIVATE_IP
  SSH user:       $ADMIN_USER

IMPORTANT: To SSH from your Windows machine through the gateway without copying
private keys onto the gateway, connect to the gateway with agent forwarding:

  ssh -A -i "C:\\Users\\Ayan\\Downloads\\Kubernetes\\Azure_setup\\Azure_ssh_keys\\k8s-gateway-key.pem" azureuser@<GATEWAY_PUBLIC_IP>

Then, from the gateway:

  ssh $ADMIN_USER@$ACTUAL_IP

After login, test internet routing through the gateway:

  curl -s https://api.ipify.org ; echo

SUMMARY
