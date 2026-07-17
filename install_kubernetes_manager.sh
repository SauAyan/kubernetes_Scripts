#!/bin/bash

KUBERNETES_VERSION=v1.35
CRIO_VERSION=v1.35

sudo swapoff -a
sudo sed -e '/swap/s/^/#/g' -i /etc/fstab

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

apt-get update
apt-get install -y software-properties-common curl

sudo apt-get update
sudo apt-get install -y software-properties-common curl

sudo bash -c "curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key | gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo bash -c "curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key | gpg --batch --yes --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg"

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/ /" | \
    sudo tee /etc/apt/sources.list.d/cri-o.list

sudo apt-get update
sudo apt-get install -y cri-o kubelet kubeadm kubectl

sudo apt-get update
sudo apt-get install -y cri-tools

systemctl start kubelet
systemctl enable kubelet
systemctl start crio.service
systemctl enable crio.service

#### NEXT STEPS ON MANAGER
# sudo kubeadm config images pull
# sudo kubeadm init --apiserver-advertise-address 10.0.0.101 --pod-network-cidr 172.17.0.0/16
# READ - output and execute commands
# Finally - install CNI - calico
# kubectl apply -f https://docs.tigera.io/calico/latest/manifests/calico.yaml
####