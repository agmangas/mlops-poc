#!/usr/bin/env bash

set -e
set -x

: ${MICROK8S_CHANNEL:="1.21"}
: ${MICROK8S_USER:="vagrant"}

snap install microk8s --classic --channel=${MICROK8S_CHANNEL}
usermod -a -G microk8s ${MICROK8S_USER}
microk8s status --wait-ready
microk8s enable dns storage helm3 dashboard

apt-get update -y && apt-get install -y python3 python-is-python3

echo -e '#!/bin/sh\nmicrok8s kubectl "$@"' >> /usr/bin/kubectl && \
chmod 755 /usr/bin/kubectl && \
kubectl version

echo -e '#!/bin/sh\nmicrok8s helm3 "$@"' >> /usr/bin/helm && \
chmod 755 /usr/bin/helm && \
helm version

wget --quiet https://dl.min.io/client/mc/release/linux-amd64/mc && \
chmod 755 mc && \
mv ./mc /usr/bin && \
mc --version