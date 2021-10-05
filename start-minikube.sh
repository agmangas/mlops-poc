#!/usr/bin/env bash

set -e
set -x

: ${MINIKUBE_MEMORY:="11980"}
: ${MINIKUBE_CPUS:="4"}
: ${KUBERNETES_VERSION:="v1.20.2"}

minikube start \
--memory=${MINIKUBE_MEMORY} \
--cpus=${MINIKUBE_CPUS} \
--kubernetes-version=${KUBERNETES_VERSION}

minikube addons enable ingress

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
spec:
  controller: k8s.io/ingress-nginx
EOF