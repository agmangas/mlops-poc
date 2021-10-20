#!/usr/bin/env bash

set -e
set -x

: ${NAMESPACE:="kserve-inference-$RANDOM"}
: ${MINIO_ENDPOINT_CLUSTER:="minio-service.tenant-tiny:9000"}
: ${MINIO_ENDPOINT_PUBLIC:="http://localhost:30100"}
: ${MINIO_ACCESS_KEY:="minio"}
: ${MINIO_SECRET_KEY:="minio123"}
: ${MODEL_PATH:=""}
: ${MODEL_NAME:=""}

TMP_DIR=$(python3 -c "import tempfile; print(tempfile.gettempdir());")
TMP_PATH=${TMP_DIR}/kserve-deploy-inference

rm -fr ${TMP_PATH} && mkdir -p ${TMP_PATH}

if [ -z "$MODEL_PATH" ]
then
    wget -O ${TMP_PATH}/model.joblib \
    https://storage.googleapis.com/kfserving-samples/models/sklearn/iris/model.joblib

    MODEL_PATH=${TMP_PATH}/model.joblib
fi

if [ -z "$MODEL_NAME" ]
then
    MODEL_NAME=${NAMESPACE}
fi

mc alias set ${NAMESPACE} ${MINIO_ENDPOINT_PUBLIC} ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY}
mc mb ${NAMESPACE}/${MODEL_NAME}
mc cp ${MODEL_PATH} ${NAMESPACE}/${MODEL_NAME}/model.joblib

kubectl create namespace ${NAMESPACE}

cat <<EOT >> ${TMP_PATH}/s3-secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: s3creds
  annotations:
    serving.kserve.io/s3-endpoint: ${MINIO_ENDPOINT_CLUSTER}
    serving.kserve.io/s3-usehttps: "0"
    serving.kserve.io/s3-region: "eu-west-1"
    serving.kserve.io/s3-useanoncredential: "false"
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: ${MINIO_ACCESS_KEY}
  AWS_SECRET_ACCESS_KEY: ${MINIO_SECRET_KEY}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sa
secrets:
  - name: s3creds
EOT

cat ${TMP_PATH}/s3-secrets.yaml

kubectl apply -n ${NAMESPACE} -f ${TMP_PATH}/s3-secrets.yaml

cat <<EOT >> ${TMP_PATH}/inference-service.yaml
apiVersion: "serving.kserve.io/v1beta1"
kind: "InferenceService"
metadata:
  name: "${MODEL_NAME}"
spec:
  predictor:
    serviceAccountName: sa
    sklearn:
      storageUri: "s3://${MODEL_NAME}"
EOT

cat ${TMP_PATH}/inference-service.yaml

for i in {1..5}
do
    kubectl apply -f ${TMP_PATH}/inference-service.yaml -n ${NAMESPACE} && break || sleep 30
done

sleep 10

kubectl get inferenceservices -n ${NAMESPACE}

for i in {1..5}
do
    (DEPLOYMENT=$(kubectl get deployments -n ${NAMESPACE} -o jsonpath='{.items[0].metadata.name}') \
    && kubectl rollout status deployment/${DEPLOYMENT} -n ${NAMESPACE}) && break || sleep 30
done

set +x

GREEN='\033[0;32m'
RESET='\033[0m'

HELP=$(cat << EOF
export INGRESS_HOST=\$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=\$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export SERVICE_HOSTNAME=\$(kubectl get inferenceservice ${MODEL_NAME} -n ${NAMESPACE} -o jsonpath='{.status.url}' | cut -d "/" -f 3)

Example cURL command (please note that the request body is specific to sklearn-iris model):

curl -v \
-H "Host: \${SERVICE_HOSTNAME}" \
http://\${INGRESS_HOST}:\${INGRESS_PORT}/v1/models/${MODEL_NAME}:predict \
-d '{"instances":[[6.8,2.8,4.8,1.4],[6,3.4,4.5,1.6]]}'
EOF
)

echo -e "${GREEN}${HELP}${RESET}"