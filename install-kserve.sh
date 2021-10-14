#!/usr/bin/env bash

set -e
set -x

: ${KSERVE_TREEISH:="v0.7.0"}

TMP_DIR=$(python -c "import tempfile; print(tempfile.gettempdir());")
TMP_PATH=${TMP_DIR}/kfserving-poc
KSERVE_REPO_PATH=${TMP_PATH}/kfserving

rm -fr ${TMP_PATH} && mkdir -p ${TMP_PATH}

git clone \
--depth 1 \
--branch ${KSERVE_TREEISH} \
https://github.com/kserve/kserve.git \
${KSERVE_REPO_PATH}

cd ${KSERVE_REPO_PATH}

./hack/quick_install.sh

kubectl create namespace kserve-test

sleep 10

for i in {1..5}
do
    kubectl apply \
    -f ${KSERVE_REPO_PATH}/docs/samples/v1beta1/sklearn/v1/sklearn.yaml \
    -n kserve-test && break || sleep 30
done

sleep 10

kubectl get inferenceservices sklearn-iris -n kserve-test

for i in {1..5}
do
    kubectl rollout status \
    deployment/sklearn-iris-predictor-default-00001-deployment \
    -n kserve-test && break || sleep 30
done

set +x

GREEN='\033[0;32m'
RESET='\033[0m'

HELP=$(cat << EOF
To send a request to the example sklearn service, run "minikube tunnel" in another terminal and then use the following cURL command.

export INGRESS_HOST=\$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=\$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export SERVICE_HOSTNAME=\$(kubectl get inferenceservice sklearn-iris -n kserve-test -o jsonpath='{.status.url}' | cut -d "/" -f 3)

curl -v \
-H "Host: \${SERVICE_HOSTNAME}" \
http://\${INGRESS_HOST}:\${INGRESS_PORT}/v1/models/sklearn-iris:predict \
-d '{"instances":[[6.8,2.8,4.8,1.4],[6,3.4,4.5,1.6]]}'
EOF
)

echo -e "${GREEN}${HELP}${RESET}"