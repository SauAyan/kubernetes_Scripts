Great—let’s build only the **gateway VM** first.

Your local gateway currently performs two jobs:

1. It gives you an SSH entry point into the cluster.
2. It acts as a NAT gateway so the private manager and worker nodes can access the internet.

We will reproduce that with one Ubuntu VM in Azure.

## Gateway design

```text
Your laptop
    |
    | SSH using public IP
    v
Azure Gateway VM
Public IP + Private IP: 10.0.0.10
    |
    | Later: SSH to private IPs
    v
Manager and worker nodes
```

We will create:

| Resource        | Value                   |
| --------------- | ----------------------- |
| Resource group  | `rg-kubernetes-lab`     |
| Region          | Central India           |
| Virtual network | `k8s-vnet`              |
| Address range   | `10.0.0.0/8`            |
| Subnet          | `k8s-subnet`            |
| Subnet range    | `10.0.0.0/24`           |
| Gateway VM      | `k8s-gateway`           |
| Private IP      | `10.0.0.10`             |
| Public IP       | Assigned by Azure       |
| OS              | Ubuntu Server 22.04 LTS |
| VM size         | `Standard_B2s`          |
| SSH port        | 22                      |

Although your notes show `10.0.0.0/8`, using `/24` for the actual subnet is more manageable and still gives you 256 addresses. The VNet itself can remain `/8`.

# Step 1: Create the resource group

In the Azure portal:

1. Search for **Resource groups**.
2. Select **Create**.
3. Enter:

```text
Subscription: Your Azure subscription
Resource group: rg-kubernetes-lab
Region: Central India
```

4. Select **Review + create**.
5. Select **Create**.

# Step 2: Create the virtual network

Search for **Virtual networks** and select **Create**.

### Basics

```text
Resource group: rg-kubernetes-lab
Virtual network name: k8s-vnet
Region: Central India
```

### IP addresses

Set the virtual-network address space to:

```text
10.0.0.0/8
```

Create or edit the subnet:

```text
Subnet name: k8s-subnet
Subnet address range: 10.0.0.0/24
```

Then select:

```text
Review + create
Create
```

All four machines will eventually be attached to this same subnet:

```text
Gateway: 10.0.0.10
Manager: 10.0.0.20
Worker 1: 10.0.0.21
Worker 2: 10.0.0.22
```

Azure assigns private addresses through each VM’s network interface. We will change the gateway allocation to static after deployment rather than manually setting the address inside Ubuntu. ([Microsoft Learn][1])

# Step 3: Create the gateway VM

Search for **Virtual machines** and select:

```text
Create
Azure virtual machine
```

## Basics tab

Enter:

```text
Resource group: rg-kubernetes-lab
Virtual machine name: k8s-gateway
Region: Central India
Availability options: No infrastructure redundancy required
Security type: Standard
Image: Ubuntu Server 22.04 LTS
Architecture: x64
Size: Standard_B2s
```

`Standard_B2s` provides:

```text
2 vCPUs
4 GB RAM
```

That is sufficient for an SSH and NAT gateway. Your handwritten configuration mentions 2 GB RAM, but 4 GB gives the operating system more room and generally avoids memory pressure.

## Administrator account

Choose:

```text
Authentication type: SSH public key
Username: azureuser
SSH public key source: Generate new key pair
Key pair name: k8s-gateway-key
```

SSH-key authentication is preferable to password authentication.

## Inbound ports

Choose:

```text
Public inbound ports: Allow selected ports
Select inbound ports: SSH (22)
```

Continue to the **Disks** tab.

# Step 4: Configure storage

For a gateway, you do not need a 200 GB disk.

Use:

```text
OS disk size: 30 GB or default
OS disk type: Standard SSD
Delete with VM: Enabled
```

Your local notes mention 20 GB. Azure’s available OS disk options may start higher depending on the selected image, which is fine.

# Step 5: Configure networking

Open the **Networking** tab.

Set:

```text
Virtual network: k8s-vnet
Subnet: k8s-subnet
Public IP: Create new
NIC network security group: Basic
Public inbound ports: Allow selected ports
Inbound ports: SSH 22
Delete public IP and NIC when VM is deleted: Enabled
```

For the public IP:

```text
Name: k8s-gateway-public-ip
SKU: Standard
Assignment: Static
```

For now, leave **IP forwarding disabled** during VM creation. We will enable it after deployment.

Select:

```text
Review + create
Create
```

Azure will prompt you to download the SSH private key.

Download and store the `.pem` file safely. Azure does not retain a downloadable copy of that private key for you.

Azure Linux VMs commonly use a public IP, an NSG rule permitting TCP 22, and an SSH key for remote access. ([Microsoft Learn][2])

# Step 6: Set the private IP to `10.0.0.10`

After deployment:

1. Open `k8s-gateway`.
2. Select **Networking** → **Network settings**.
3. Select the gateway’s **Network interface**.
4. Select **IP configurations**.
5. Select `ipconfig1`.
6. Change:

```text
Private IP allocation: Static
Private IP address: 10.0.0.10
```

7. Select **Save**.

Do not configure `10.0.0.10` manually through Ubuntu Netplan. Keep Ubuntu using DHCP because Azure controls the NIC-level private-IP assignment. A mismatch between the OS configuration and Azure NIC configuration can make the VM unreachable. ([Microsoft Learn][1])

# Step 7: Restrict SSH access

The default SSH rule may allow access from anywhere.

Open:

```text
k8s-gateway
Networking
Network settings
Inbound port rules
```

Select the SSH rule and change the source to:

```text
Source: My IP address
Destination port: 22
Protocol: TCP
Action: Allow
```

This means only your current public IP can SSH into the gateway. Network Security Groups filter traffic based on source, destination, protocol, and port. ([Microsoft Learn][3])

Be aware that your home public IP may change. In that case, update the NSG rule with your new IP.

# Step 8: Enable Azure-side IP forwarding

The gateway must later forward traffic from manager and worker nodes.

Go to:

```text
k8s-gateway
Networking
Network settings
Network interface
IP configurations
IP forwarding
```

Set:

```text
IP forwarding: Enabled
```

Select **Save**.

Azure requires forwarding to be enabled on the gateway NIC when the VM is acting as a network virtual appliance or router. ([Microsoft Learn][4])

# Step 9: Connect from Windows

Move the downloaded key somewhere permanent, for example:

```text
C:\Users\<your-user>\.ssh\k8s-gateway-key.pem
```

Get the gateway public IP from the VM Overview page.

From PowerShell:

```powershell
ssh -i "$HOME\.ssh\k8s-gateway-key.pem" azureuser@<GATEWAY-PUBLIC-IP>
```

Example:

```powershell
ssh -i "$HOME\.ssh\k8s-gateway-key.pem" azureuser@20.204.100.50
```

At the first connection prompt:

```text
Are you sure you want to continue connecting?
```

Enter:

```text
yes
```

After login, confirm the hostname and private address:

```bash
hostname
ip -br addr
```

You should see:

```text
k8s-gateway
```

and an interface containing:

```text
10.0.0.10
```

# Step 10: Update Ubuntu and install required packages

Inside the gateway VM:

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y openssh-server iptables-persistent
```

Check SSH:

```bash
sudo systemctl enable --now ssh
sudo systemctl status ssh
```

It should show:

```text
active (running)
```

# Step 11: Enable Linux IP forwarding

Azure NIC forwarding alone is not sufficient. Ubuntu must also forward packets.

Run:

```bash
sudo tee /etc/sysctl.d/99-kubernetes-gateway.conf > /dev/null <<'EOF'
net.ipv4.ip_forward=1
EOF
```

Apply it:

```bash
sudo sysctl --system
```

Verify:

```bash
sysctl net.ipv4.ip_forward
```

Expected:

```text
net.ipv4.ip_forward = 1
```

Azure’s routing guidance requires IP forwarding to be enabled both on the Azure network interface and in the gateway VM operating system. ([Microsoft Learn][5])

# Step 12: Configure NAT

Your gateway’s Azure network interface will usually be named `eth0`.

Check:

```bash
ip route
```

You will likely see something similar to:

```text
default via 10.0.0.1 dev eth0
```

Create the NAT rule:

```bash
sudo iptables -t nat -A POSTROUTING \
  -s 10.0.0.0/24 \
  -o eth0 \
  -j MASQUERADE
```

Allow forwarding:

```bash
sudo iptables -A FORWARD \
  -s 10.0.0.0/24 \
  -o eth0 \
  -j ACCEPT

sudo iptables -A FORWARD \
  -d 10.0.0.0/24 \
  -m conntrack \
  --ctstate ESTABLISHED,RELATED \
  -i eth0 \
  -j ACCEPT
```

Save the rules:

```bash
sudo netfilter-persistent save
sudo netfilter-persistent reload
```

Verify:

```bash
sudo iptables -t nat -L POSTROUTING -n -v
sudo iptables -L FORWARD -n -v
```

## Important Azure difference

Creating the NAT rule on the gateway is only one part of the configuration. After the manager and worker nodes are created, we must create an Azure **route table** that directs their outbound traffic to:

```text
Next hop type: Virtual appliance
Next hop address: 10.0.0.10
```

Without that route table, Azure will not automatically send the other VMs’ traffic through your gateway. Azure user-defined routes are how traffic is explicitly directed through a network virtual appliance. ([Microsoft Learn][5])

We will configure that after creating the private manager and worker nodes.

# Gateway completion checklist

At the end of this stage, verify:

```bash
hostname
```

Expected:

```text
k8s-gateway
```

Verify the private IP:

```bash
hostname -I
```

Expected to include:

```text
10.0.0.10
```

Verify SSH:

```bash
sudo systemctl is-active ssh
```

Expected:

```text
active
```

Verify forwarding:

```bash
sysctl net.ipv4.ip_forward
```

Expected:

```text
net.ipv4.ip_forward = 1
```

Verify internet access:

```bash
curl -I https://www.microsoft.com
```

Once these checks work, the gateway VM is ready. The next stage is creating the manager VM with **private IP only**, then connecting to it through `k8s-gateway`.

[1]: https://learn.microsoft.com/vi-vn/azure/virtual-network/ip-services/virtual-networks-static-private-ip?utm_source=chatgpt.com "Create a virtual machine with a static private IP address"
[2]: https://learn.microsoft.com/en-us/azure/virtual-machines/linux-vm-connect?utm_source=chatgpt.com "Connect to a Linux VM - Azure Virtual Machines"
[3]: https://learn.microsoft.com/en-us/azure/virtual-network/tutorial-filter-network-traffic?utm_source=chatgpt.com "Tutorial: Filter network traffic with a network security group"
[4]: https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-network-interface?utm_source=chatgpt.com "Create, Change, or Delete Azure Network Interfaces"
[5]: https://learn.microsoft.com/en-us/azure/virtual-network/tutorial-create-route-table?utm_source=chatgpt.com "Tutorial: Route network traffic with a route table"
