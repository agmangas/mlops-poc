#!/usr/bin/env bash

set -e
set -x

: ${MINIKUBE_MEMORY:="11980"}
: ${MINIKUBE_CPUS:="4"}
: ${KUBERNETES_VERSION:="v1.20.2"}
: ${KFSERVING_TREEISH:="v0.6.1"}
: ${KFSERVING_API_VERSION:="v1beta1"}

if [[ -z "$SKIP_MINIKUBE_START" ]]; then
    minikube start \
    --memory=${MINIKUBE_MEMORY} \
    --cpus=${MINIKUBE_CPUS} \
    --kubernetes-version=${KUBERNETES_VERSION}
fi

CURR_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd )"
TMP_DIR=$(python -c "import tempfile; print(tempfile.gettempdir());")
TMP_PATH=${TMP_DIR}/kfserving-poc
KFSERVING_REPO_PATH=${TMP_PATH}/kfserving

rm -fr ${TMP_PATH} && mkdir -p ${TMP_PATH}

git clone \
--depth 1 \
--branch ${KFSERVING_TREEISH} \
git@github.com:kserve/kserve.git \
${KFSERVING_REPO_PATH}

cd ${KFSERVING_REPO_PATH}

./hack/quick_install.sh

kubectl create namespace kfserving-test

for i in {1..5}
do
    kubectl apply \
    -f ./docs/samples/${KFSERVING_API_VERSION}/sklearn/v1/sklearn.yaml \
    -n kfserving-test && break || sleep 30
done

sleep 10

for i in {1..5}
do
    kubectl rollout status \
    deployment/sklearn-iris-predictor-default-00001-deployment \
    -n kfserving-test && break || sleep 30
done

cat << EOF

To send a request to the example sklearn service, run "minikube tunnel" in another terminal and then use the following cURL command.

export INGRESS_HOST=\$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=\$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export SERVICE_HOSTNAME=\$(kubectl get inferenceservice sklearn-iris -n kfserving-test -o jsonpath='{.status.url}' | cut -d "/" -f 3)

curl -v \
-H "Host: \${SERVICE_HOSTNAME}" \
http://\${INGRESS_HOST}:\${INGRESS_PORT}/v1/models/sklearn-iris:predict \
-d @${KFSERVING_REPO_PATH}/docs/samples/${KFSERVING_API_VERSION}/sklearn/v1/iris-input.json

The Models UI web app is available on:

http://\${INGRESS_HOST}:\${INGRESS_PORT}/models/
EOF