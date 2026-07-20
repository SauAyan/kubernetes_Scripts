#!/usr/bin/env bash
set -Eeuo pipefail

# Creates an Azure Ubuntu gateway/jump-box for a future self-managed Kubernetes lab.
# Run from Azure Cloud Shell (Bash) or any Bash terminal with Azure CLI installed.
#
# Usage:
#   chmod +x setup_azure_k8s_gateway.sh
#   ./setup_azure_k8s_gateway.sh <YOUR_PUBLIC_IP_OR_CIDR>
#
# Examples:
#   ./setup_azure_k8s_gateway.sh 203.0.113.25
#   ./setup_azure_k8s_gateway.sh 203.0.113.25/32
#
# Optional overrides:
#   LOCATION=centralindia VM_SIZE=Standard_B2s ./setup_azure_k8s_gateway.sh 203.0.113.25/32

SSH_SOURCE_INPUT="${1:-${SSH_SOURCE_CIDR:-}}"

if [[ -z "$SSH_SOURCE_INPUT" ]]; then
  echo "ERROR: Supply your public IP address or CIDR as the first argument."
  echo "Example: $0 203.0.113.25/32"
  exit 1
fi

# Convert a single IPv4 address to /32. Preserve an already supplied CIDR.
if [[ "$SSH_SOURCE_INPUT" == */* ]]; then
  SSH_SOURCE_CIDR="$SSH_SOURCE_INPUT"
else
  SSH_SOURCE_CIDR="${SSH_SOURCE_INPUT}/32"
fi

# -------------------------
# Configurable values
# -------------------------
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-kubernetes-lab}"
LOCATION="${LOCATION:-centralindia}"
VNET_NAME="${VNET_NAME:-k8s-vnet}"
VNET_CIDR="${VNET_CIDR:-10.0.0.0/16}"

# Separate subnets are intentional. The future cluster subnet can route through
# the gateway without causing the gateway itself to route back to itself.
GATEWAY_SUBNET_NAME="${GATEWAY_SUBNET_NAME:-gateway-subnet}"
GATEWAY_SUBNET_CIDR="${GATEWAY_SUBNET_CIDR:-10.0.0.0/24}"
CLUSTER_SUBNET_NAME="${CLUSTER_SUBNET_NAME:-cluster-subnet}"
CLUSTER_SUBNET_CIDR="${CLUSTER_SUBNET_CIDR:-10.0.1.0/24}"

VM_NAME="${VM_NAME:-k8s-gateway}"
NIC_NAME="${NIC_NAME:-k8s-gateway-nic}"
NSG_NAME="${NSG_NAME:-k8s-gateway-nsg}"
PUBLIC_IP_NAME="${PUBLIC_IP_NAME:-k8s-gateway-public-ip}"
PRIVATE_IP="${PRIVATE_IP:-10.0.0.10}"
ADMIN_USERNAME="${ADMIN_USERNAME:-azureuser}"
VM_SIZE="${VM_SIZE:-Standard_B2s}"
VM_IMAGE="${VM_IMAGE:-Ubuntu2204}"
SSH_PUBLIC_KEY_FILE="${SSH_PUBLIC_KEY_FILE:-$HOME/.ssh/id_rsa.pub}"
SSH_PRIVATE_KEY_FILE="${SSH_PRIVATE_KEY_FILE:-$HOME/.ssh/id_rsa}"
ROUTE_TABLE_NAME="${ROUTE_TABLE_NAME:-k8s-cluster-route-table}"
ROUTE_NAME="${ROUTE_NAME:-default-via-k8s-gateway}"

log() { printf '\n==> %s\n' "$*"; }
exists() { "$@" >/dev/null 2>&1; }

command -v az >/dev/null 2>&1 || {
  echo "ERROR: Azure CLI ('az') is not installed."
  exit 1
}

log "Checking Azure sign-in"
az account show >/dev/null 2>&1 || {
  echo "Not signed in. Starting 'az login'..."
  az login >/dev/null
}

if [[ ! -f "$SSH_PUBLIC_KEY_FILE" ]]; then
  log "SSH public key not found; generating one at $SSH_PRIVATE_KEY_FILE"
  mkdir -p "$(dirname "$SSH_PRIVATE_KEY_FILE")"
  ssh-keygen -t rsa -b 4096 -f "$SSH_PRIVATE_KEY_FILE" -N ""
fi

log "Creating/updating resource group: $RESOURCE_GROUP"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none

if ! exists az network vnet show -g "$RESOURCE_GROUP" -n "$VNET_NAME"; then
  log "Creating VNet: $VNET_NAME ($VNET_CIDR)"
  az network vnet create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VNET_NAME" \
    --location "$LOCATION" \
    --address-prefixes "$VNET_CIDR" \
    --output none
else
  log "VNet already exists: $VNET_NAME"
fi

if ! exists az network vnet subnet show -g "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" -n "$GATEWAY_SUBNET_NAME"; then
  log "Creating gateway subnet: $GATEWAY_SUBNET_NAME ($GATEWAY_SUBNET_CIDR)"
  az network vnet subnet create \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$GATEWAY_SUBNET_NAME" \
    --address-prefixes "$GATEWAY_SUBNET_CIDR" \
    --output none
else
  log "Gateway subnet already exists"
fi

if ! exists az network vnet subnet show -g "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" -n "$CLUSTER_SUBNET_NAME"; then
  log "Creating future cluster subnet: $CLUSTER_SUBNET_NAME ($CLUSTER_SUBNET_CIDR)"
  az network vnet subnet create \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$CLUSTER_SUBNET_NAME" \
    --address-prefixes "$CLUSTER_SUBNET_CIDR" \
    --output none
else
  log "Cluster subnet already exists"
fi

if ! exists az network nsg show -g "$RESOURCE_GROUP" -n "$NSG_NAME"; then
  log "Creating gateway NSG: $NSG_NAME"
  az network nsg create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NSG_NAME" \
    --location "$LOCATION" \
    --output none
else
  log "Gateway NSG already exists"
fi

if exists az network nsg rule show -g "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" -n AllowSSHFromMyIP; then
  log "Updating SSH rule for source $SSH_SOURCE_CIDR"
  az network nsg rule update \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "$NSG_NAME" \
    --name AllowSSHFromMyIP \
    --priority 100 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes "$SSH_SOURCE_CIDR" \
    --source-port-ranges '*' \
    --destination-address-prefixes '*' \
    --destination-port-ranges 22 \
    --output none
else
  log "Allowing SSH only from $SSH_SOURCE_CIDR"
  az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "$NSG_NAME" \
    --name AllowSSHFromMyIP \
    --priority 100 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes "$SSH_SOURCE_CIDR" \
    --source-port-ranges '*' \
    --destination-address-prefixes '*' \
    --destination-port-ranges 22 \
    --output none
fi

if ! exists az network public-ip show -g "$RESOURCE_GROUP" -n "$PUBLIC_IP_NAME"; then
  log "Creating static Standard public IP: $PUBLIC_IP_NAME"
  az network public-ip create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$PUBLIC_IP_NAME" \
    --location "$LOCATION" \
    --sku Standard \
    --allocation-method Static \
    --output none
else
  log "Public IP already exists"
fi

if ! exists az network nic show -g "$RESOURCE_GROUP" -n "$NIC_NAME"; then
  log "Creating NIC with static private IP $PRIVATE_IP and Azure IP forwarding enabled"
  az network nic create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NIC_NAME" \
    --location "$LOCATION" \
    --vnet-name "$VNET_NAME" \
    --subnet "$GATEWAY_SUBNET_NAME" \
    --network-security-group "$NSG_NAME" \
    --public-ip-address "$PUBLIC_IP_NAME" \
    --private-ip-address "$PRIVATE_IP" \
    --ip-forwarding true \
    --output none
else
  log "NIC already exists; enforcing IP forwarding"
  az network nic update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NIC_NAME" \
    --ip-forwarding true \
    --output none
fi

CLOUD_INIT_FILE="$(mktemp)"
trap 'rm -f "$CLOUD_INIT_FILE"' EXIT

cat > "$CLOUD_INIT_FILE" <<EOF_CLOUD
#cloud-config
package_update: true
package_upgrade: true
packages:
  - openssh-server
  - iptables-persistent
  - netfilter-persistent

write_files:
  - path: /etc/sysctl.d/99-kubernetes-gateway.conf
    owner: root:root
    permissions: '0644'
    content: |
      net.ipv4.ip_forward=1

  - path: /usr/local/sbin/configure-k8s-gateway.sh
    owner: root:root
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      set -Eeuo pipefail
      SUBNET='${CLUSTER_SUBNET_CIDR}'
      WAN_IF=\$(ip route show default | awk '{print \$5; exit}')
      test -n "\$WAN_IF"

      sysctl --system

      iptables -t nat -C POSTROUTING -s "\$SUBNET" -o "\$WAN_IF" -j MASQUERADE 2>/dev/null || \\
        iptables -t nat -A POSTROUTING -s "\$SUBNET" -o "\$WAN_IF" -j MASQUERADE

      iptables -C FORWARD -s "\$SUBNET" -o "\$WAN_IF" -j ACCEPT 2>/dev/null || \\
        iptables -A FORWARD -s "\$SUBNET" -o "\$WAN_IF" -j ACCEPT

      iptables -C FORWARD -d "\$SUBNET" -i "\$WAN_IF" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \\
        iptables -A FORWARD -d "\$SUBNET" -i "\$WAN_IF" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

      netfilter-persistent save
      systemctl enable --now ssh

runcmd:
  - [bash, /usr/local/sbin/configure-k8s-gateway.sh]
EOF_CLOUD

if ! exists az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME"; then
  log "Creating Ubuntu gateway VM: $VM_NAME"
  az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --location "$LOCATION" \
    --nics "$NIC_NAME" \
    --image "$VM_IMAGE" \
    --size "$VM_SIZE" \
    --admin-username "$ADMIN_USERNAME" \
    --ssh-key-values "$SSH_PUBLIC_KEY_FILE" \
    --custom-data "$CLOUD_INIT_FILE" \
    --os-disk-size-gb 30 \
    --storage-sku StandardSSD_LRS \
    --output none
else
  log "VM already exists: $VM_NAME"
fi

# Create the route table now for the future manager/worker subnet. It is NOT
# associated with the gateway subnet, avoiding a self-routing loop.
if ! exists az network route-table show -g "$RESOURCE_GROUP" -n "$ROUTE_TABLE_NAME"; then
  log "Creating route table for future Kubernetes nodes"
  az network route-table create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$ROUTE_TABLE_NAME" \
    --location "$LOCATION" \
    --output none
else
  log "Route table already exists"
fi

if exists az network route-table route show -g "$RESOURCE_GROUP" --route-table-name "$ROUTE_TABLE_NAME" -n "$ROUTE_NAME"; then
  az network route-table route update \
    --resource-group "$RESOURCE_GROUP" \
    --route-table-name "$ROUTE_TABLE_NAME" \
    --name "$ROUTE_NAME" \
    --address-prefix 0.0.0.0/0 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address "$PRIVATE_IP" \
    --output none
else
  az network route-table route create \
    --resource-group "$RESOURCE_GROUP" \
    --route-table-name "$ROUTE_TABLE_NAME" \
    --name "$ROUTE_NAME" \
    --address-prefix 0.0.0.0/0 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address "$PRIVATE_IP" \
    --output none
fi

log "Associating route table with future cluster subnet only"
az network vnet subnet update \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --name "$CLUSTER_SUBNET_NAME" \
  --route-table "$ROUTE_TABLE_NAME" \
  --output none

PUBLIC_IP=$(az network public-ip show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$PUBLIC_IP_NAME" \
  --query ipAddress \
  --output tsv)

log "Waiting briefly for cloud-init provisioning"
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "cloud-init status --wait || true; sysctl net.ipv4.ip_forward; systemctl is-active ssh; iptables -t nat -S POSTROUTING" \
  --query 'value[0].message' \
  --output tsv

cat <<EOF_SUMMARY

Gateway setup complete.

Resource group:       $RESOURCE_GROUP
Region:               $LOCATION
Gateway VM:           $VM_NAME
Gateway private IP:   $PRIVATE_IP
Gateway public IP:    $PUBLIC_IP
Gateway subnet:       $GATEWAY_SUBNET_CIDR
Future cluster subnet:$CLUSTER_SUBNET_CIDR
SSH allowed from:     $SSH_SOURCE_CIDR

Connect with:
  ssh -i "$SSH_PRIVATE_KEY_FILE" ${ADMIN_USERNAME}@${PUBLIC_IP}

Verify after login:
  hostname
  ip -br addr
  sysctl net.ipv4.ip_forward
  sudo iptables -t nat -L POSTROUTING -n -v
  sudo iptables -L FORWARD -n -v

IMPORTANT: Future manager and worker VMs should be created in:
  VNet:   $VNET_NAME
  Subnet: $CLUSTER_SUBNET_NAME ($CLUSTER_SUBNET_CIDR)
They should not receive public IP addresses.
EOF_SUMMARY
