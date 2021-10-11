#!/usr/bin/env bash

set -e
set -x

: ${VERSION_DOCKER:="20.10.6"}
: ${VERSION_COMPOSE:="1.29.1"}
: ${UNPRIVILEGED_USER:="vagrant"}
: ${KIND_TAG:="v1.20.2"}
: ${KIND_CONFIG:="/vagrant/kind-config.yml"}
: ${KUBECTL_VERSION:="v1.21.5"}

# Docker and Compose

apt-get update -y && apt-get install -y curl
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

su - ${UNPRIVILEGED_USER} -c "kind create cluster --image kindest/node:${KIND_TAG} --config ${KIND_CONFIG}"

# Kubectl

curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
kubectl version --client && \
su - ${UNPRIVILEGED_USER} -c "kubectl config current-context"

# Helm

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && \
helm version