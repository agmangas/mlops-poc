#!/usr/bin/env bash

set -e
set -x

: ${VERSION_DOCKER:="20.10.6"}
: ${VERSION_COMPOSE:="1.29.1"}
: ${KIND_TAG:="v1.20.2"}
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
usermod -aG docker vagrant

curl -L \
https://github.com/docker/compose/releases/download/${VERSION_COMPOSE}/docker-compose-`uname -s`-`uname -m` \
-o /usr/local/bin/docker-compose

chmod +x /usr/local/bin/docker-compose
docker-compose --version

# Python 3

add-apt-repository -y ppa:deadsnakes/ppa && apt-get update -y && apt-get install -y python3.7
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py && python3.7 get-pip.py && rm get-pip.py

if [ -f "/vagrant/scripts/requirements.txt" ]; then
    pip3.7 install virtualenv
    virtualenv --python python3.7 /home/vagrant/venv
    /home/vagrant/venv/bin/python -m pip install --upgrade pip
    /home/vagrant/venv/bin/pip install -r /vagrant/scripts/requirements.txt
fi

# MinIO client

wget --quiet https://dl.min.io/client/mc/release/linux-amd64/mc && \
chmod 755 mc && \
mv ./mc /usr/bin && \
mc --version

# Initialize the local registry service

REG_NAME="kind-registry"
REG_PORT="5000"

running="$(docker inspect -f '{{.State.Running}}' "${REG_NAME}" 2>/dev/null || true)"

if [ "${running}" != 'true' ]; then
    docker run -d --restart=always \
    -p ${REG_PORT}:5000 --name "${REG_NAME}" registry:2
fi

# Kind

curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.11.1/kind-linux-amd64 && \
chmod +x ./kind && \
mv ./kind /usr/local/bin/kind

sudo -H -u vagrant \
kind create cluster \
--image kindest/node:${KIND_TAG} \
--config /vagrant/kind-config.yml

mkdir -p ~/.kube && (cp /home/vagrant/.kube/config ~/.kube/config || true)

# Kubectl

curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
kubectl version --client && \
kubectl config current-context

# Configure the local registry

docker network connect "kind" "${REG_NAME}" || true

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REG_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

# Build the transformer image

if [ -f "/vagrant/transformer.Dockerfile" ]; then
    docker build \
    -t localhost:${REG_PORT}/sklearn-transformer:latest \
    -f /vagrant/transformer.Dockerfile \
    /vagrant
    
    docker push localhost:${REG_PORT}/sklearn-transformer:latest
fi

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