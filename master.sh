#!/usr/bin/bash
set -e

# Set hostname
echo "-------------Setting hostname-------------"
hostnamectl set-hostname $1

# Disable swap
echo "-------------Disabling swap-------------"
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Install Containerd
echo "-------------Installing Containerd-------------"
wget https://github.com/containerd/containerd/releases/download/v1.7.4/containerd-1.7.4-linux-amd64.tar.gz
tar Cxzvf /usr/local containerd-1.7.4-linux-amd64.tar.gz
wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
mkdir -p /usr/local/lib/systemd/system
mv containerd.service /usr/local/lib/systemd/system/containerd.service
systemctl daemon-reload
systemctl enable --now containerd

# Install Runc
echo "-------------Installing Runc-------------"
wget https://github.com/opencontainers/runc/releases/download/v1.1.9/runc.amd64
install -m 755 runc.amd64 /usr/local/sbin/runc

# Install CNI
echo "-------------Installing CNI-------------"
wget https://github.com/containernetworking/plugins/releases/download/v1.2.0/cni-plugins-linux-amd64-v1.2.0.tgz
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.2.0.tgz

# Install CRICTL
echo "-------------Installing CRICTL-------------"
VERSION="v1.28.0" # check latest version in /releases page
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$VERSION/crictl-$VERSION-linux-amd64.tar.gz
tar zxvf crictl-$VERSION-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-$VERSION-linux-amd64.tar.gz

cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
pull-image-on-create: false
EOF

# Forwarding IPv4 and letting iptables see bridged traffic
echo "-------------Setting IPTables-------------"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter

EOF
modprobe overlay
modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward
modprobe br_netfilter
sysctl -p /etc/sysctl.conf

# Install kubectl, kubelet and kubeadm
echo "-------------Installing Kubectl, Kubelet and Kubeadm-------------"
apt-get install -y apt-transport-https ca-certificates curl
mkdir /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

# apt install -y kubelet kubeadm kubectl
# apt update -y
# apt install -y kubeadm=1.29.1-1.1 kubelet=1.29.1-1.1 kubectl=1.29.1-1.1
# apt-mark hold kubelet kubeadm kubectl

apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# systemctl enable --now kubelet

echo "-------------Printing Kubeadm version-------------"
kubeadm version

echo "-------------Pulling Kueadm Images -------------"
kubeadm config images pull

echo "-------------Running kubeadm init-------------"
kubeadm init

echo "-------------Copying Kubeconfig-------------"
mkdir -p /root/.kube
cp -iv /etc/kubernetes/admin.conf /root/.kube/config
sudo chown $(id -u):$(id -g) /root/.kube/config

echo "-------------Exporting Kubeconfig-------------"
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "-------------Deploying Weavenet Pod Networking-------------"
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml

echo "-------------Creating file with join command-------------"
echo `kubeadm token create --print-join-command` > ./join-command.sh

cat ./join-command.sh

echo "-------------End of section join command-------------"

echo "-------------Install Helm-------------"
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

echo "--------------------------"
echo "      HELM SECTION"
echo "--------------------------"
echo "-------------Install cert-manager-------------"
helm repo add jetstack https://charts.jetstack.io

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.12.4 \
   --set installCRDs=true

echo "-------------GitHub Authentication-------------"
kubectl create secret generic controller-manager -n actions-runner-system 
--from-literal=app-id=<APP_ID>
--from-literal=installation-id=<INSTALLATION_ID>
--from-literal=private-key=<PRIVATE_KEY>

echo "-------------Install ARC-------------"
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm upgrade --install --namespace actions-runner-system --create-namespace -f values.yaml \
             --wait actions-runner-controller actions-runner-controller/actions-runner-controller





