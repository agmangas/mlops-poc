#!/usr/bin/env bash

set -e
set -x

: ${PUBLIC_PORT:="30300"}
: ${CONTAINER_NAME:="kserve_proxy"}
: ${IMAGE_NAME:="kserve-proxy"}

TMP_DIR=$(python3 -c "import tempfile; print(tempfile.gettempdir());")
TMP_PATH=${TMP_DIR}/kserve-proxy

rm -fr ${TMP_PATH} && mkdir -p ${TMP_PATH} && cd ${TMP_PATH}

INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')

cat <<EOT >> ${TMP_PATH}/haproxy.cfg
defaults
  log global
  mode tcp
  timeout connect 5000ms
  timeout client 120000ms
  timeout server 120000ms

listen kserve_proxy
  bind 0.0.0.0:${PUBLIC_PORT}
  mode tcp
  balance roundrobin
  server kserve_backend ${INGRESS_HOST}:${INGRESS_PORT}
EOT

cat ${TMP_PATH}/haproxy.cfg

cat <<EOT >> ${TMP_PATH}/Dockerfile
FROM haproxy:1.8
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
EOT

cat ${TMP_PATH}/Dockerfile

docker build -t ${IMAGE_NAME} ${TMP_PATH}
docker rm -f ${CONTAINER_NAME} || true
docker run -d --network host --restart unless-stopped --name ${CONTAINER_NAME} ${IMAGE_NAME}
