| Machine | Role                                             | Hostname      |  Private IP | Public IP | Subnet                           | vCPU |   RAM |                 OS Disk | OS                      | SSH Access                                |
| ------- | ------------------------------------------------ | ------------- | ----------: | --------- | -------------------------------- | ---: | ----: | ----------------------: | ----------------------- | ----------------------------------------- |
| Gateway | Bastion, routing, NAT, outbound internet gateway | `k8s-gateway` | `10.0.0.10` | Yes       | `gateway-subnet` — `10.0.0.0/24` |    2 | 4 GiB | Approximately 30–50 GiB | Ubuntu Server 22.04 LTS | Directly from Windows using its public IP |
| Manager | Kubernetes control-plane node                    | `k8s-manager` | `10.0.1.10` | No        | `cluster-subnet` — `10.0.1.0/24` |    2 | 4 GiB |     50 GiB Standard SSD | Ubuntu Server 22.04 LTS | Through the gateway                       |
| Node 1  | Kubernetes worker node                           | `k8s-node-1`  | `10.0.1.11` | No        | `cluster-subnet` — `10.0.1.0/24` |    2 | 4 GiB |     50 GiB Standard SSD | Ubuntu Server 22.04 LTS | Through the gateway                       |
| Node 2  | Kubernetes worker node                           | `k8s-node-2`  | `10.0.1.12` | No        | `cluster-subnet` — `10.0.1.0/24` |    2 | 4 GiB |     50 GiB Standard SSD | Ubuntu Server 22.04 LTS | Through the gateway                       |
| Node 3  | Kubernetes worker node                           | `k8s-node-3`  | `10.0.1.13` | No        | `cluster-subnet` — `10.0.1.0/24` |    2 | 4 GiB |     50 GiB Standard SSD | Ubuntu Server 22.04 LTS | Through the gateway                       |

## Network layout

```text
Your Windows machine
        |
        | SSH using gateway public IP
        v
k8s-gateway
10.0.0.10
        |
        | Azure route table + NAT
        v
------------------------------------------------
Cluster subnet: 10.0.1.0/24

k8s-manager   10.0.1.10
k8s-node-1    10.0.1.11
k8s-node-2    10.0.1.12
k8s-node-3    10.0.1.13
```

## Gateway configuration

| Setting                        | Value                          |
| ------------------------------ | ------------------------------ |
| Azure NIC IP forwarding        | Enabled                        |
| Ubuntu IP forwarding           | `net.ipv4.ip_forward = 1`      |
| NAT                            | `iptables MASQUERADE`          |
| Gateway private IP             | `10.0.0.10`                    |
| Cluster route next hop         | `VirtualAppliance → 10.0.0.10` |
| SSH source                     | Restricted to your public IP   |
| Worker/manager internet access | Through the gateway            |

## SSH paths

From Windows to gateway:

```cmd
ssh -A -i "C:\Users\Ayan\Downloads\Kubernetes\Azure_setup\Azure_ssh_keys\k8s-gateway-key.pem" azureuser@<GATEWAY_PUBLIC_IP>
```

From the gateway:

```bash
ssh azureuser@10.0.1.10
ssh azureuser@10.0.1.11
ssh azureuser@10.0.1.12
ssh azureuser@10.0.1.13
```

Your cluster currently has **1 gateway, 1 control-plane candidate, and 3 worker nodes**, with all Kubernetes machines kept private behind the gateway.
