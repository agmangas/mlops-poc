#!/usr/bin/env bash

set -e
set -x

: ${MINIO_NAMESPACE:="minio-operator"}
: ${MINIO_OP_TREEISH:="v4.2.10"}

CURR_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd )"
TMP_DIR=$(python -c "import tempfile; print(tempfile.gettempdir());")
MINIO_OP_REPO_PATH=${TMP_DIR}/minio-operator

rm -fr ${MINIO_OP_REPO_PATH}
trap 'rm -fr ${MINIO_OP_REPO_PATH}' EXIT

git clone \
--depth 1 \
--branch ${MINIO_OP_TREEISH} \
https://github.com/minio/operator.git \
${MINIO_OP_REPO_PATH}

helm install \
--namespace ${MINIO_NAMESPACE} \
--create-namespace \
--generate-name \
--set tenants=null \
${MINIO_OP_REPO_PATH}/helm/minio-operator

if [ -d "/vagrant/minio-tenant" ]; then
    kubectl apply -k /vagrant/minio-tenant/tenant-tiny-custom
else 
    kubectl apply -k ${CURR_DIR}/minio-tenant/tenant-tiny-custom
fi

set +x

GREEN='\033[0;32m'
RESET='\033[0m'

HELP=$(cat << EOF
To access the MinIO Operator console, forward the port for the console service:

kubectl --namespace ${MINIO_NAMESPACE} port-forward --address=0.0.0.0 svc/console 9090:9090

The console web app will now be available on http://localhost:9090. You can get a JWT token for authentication with:

kubectl get secret $(kubectl get serviceaccount console-sa --namespace ${MINIO_NAMESPACE} -o jsonpath="{.secrets[0].name}") --namespace ${MINIO_NAMESPACE} -o jsonpath="{.data.token}" | base64 --decode

To access the example Tenant, forward the port for the Tenant minio service:

kubectl --namespace tenant-tiny port-forward --address=0.0.0.0 svc/minio 8080:80

You can test access to the example Tenant with the MinIO client:

docker run --rm -it --entrypoint=/bin/bash minio/mc -c "mc alias set tiny http://$(hostname):8080 minio minio123 && mc --debug tree tiny"
EOF
)

echo -e "${GREEN}${HELP}${RESET}"
