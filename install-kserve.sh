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