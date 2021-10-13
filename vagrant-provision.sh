#!/usr/bin/env bash

set -e
set -x

: ${VERSION_DOCKER:="20.10.6"}
: ${VERSION_COMPOSE:="1.29.1"}
: ${UNPRIVILEGED_USER:="vagrant"}
: ${KIND_TAG:="v1.20.2"}
: ${KIND_CONFIG:="/vagrant/kind-config.yml"}
: ${KUBECTL_VERSION:="v1.21.5"}

debconf-set-selections <<EOF
iptables-persistent iptables-persistent/autosave_v4 boolean true
iptables-persistent iptables-persistent/autosave_v6 boolean true
EOF

DEBIAN_FRONTEND=noninteractive apt-get update -y && apt-get install -y \
curl \
iptables-persistent

# Docker and Compose

curl -fsSL https://get.docker.com -o get-docker.sh
VERSION=${VERSION_DOCKER} sh get-docker.sh
usermod -aG docker ${UNPRIVILEGED_USER}
curl -L https://github.com/docker/compose/releases/download/${VERSION_COMPOSE}/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
docker-compose --version

# Python 3

apt-get update -y && apt-get install -y python3 python-is-python3

# MinIO client

wget --quiet https://dl.min.io/client/mc/release/linux-amd64/mc && \
chmod 755 mc && \
mv ./mc /usr/bin && \
mc --version

# Kind

curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.11.1/kind-linux-amd64 && \
chmod +x ./kind && \
mv ./kind /usr/local/bin/kind
sudo -H -u ${UNPRIVILEGED_USER} kind create cluster --image kindest/node:${KIND_TAG} --config ${KIND_CONFIG}
mkdir -p ~/.kube && (cp /home/${UNPRIVILEGED_USER}/.kube/config ~/.kube/config || true)

# Kubectl

curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
kubectl version --client && \
kubectl config current-context

# Helm

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && \
helm version

# MetalLB

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/master/manifests/namespace.yaml
kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/master/manifests/metallb.yaml

sleep 30

while true
do
    LB_PODS=$(kubectl get pods -n metallb-system)
    NUM_PENDING=$(echo -n ${LB_PODS} | grep -Fo "Pending" | wc -l)
    
    if [[ $NUM_PENDING -eq 0 ]]; then
        break
    fi
    
    sleep 15
done

DOCKER_CIDR=$(echo $(docker network inspect -f '{{.IPAM.Config}}' kind) | grep -aoP '\d+\.\d+\.\d+\.\d+\/\d+')
BASE_IP=$(echo ${DOCKER_CIDR} | grep -aoP "^\d+\.\d+\.\d+")

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - ${BASE_IP}.200-${BASE_IP}.250
EOF