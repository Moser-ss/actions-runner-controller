#!/usr/bin/env bash

set -e

tpe=${ACCEPTANCE_TEST_SECRET_TYPE}

VALUES_FILE=${VALUES_FILE:-$(dirname $0)/values.yaml}

if [ "${tpe}" == "token" ]; then
  if ! kubectl get secret controller-manager -n actions-runner-system >/dev/null; then
    kubectl create secret generic controller-manager \
      -n actions-runner-system \
      --from-literal=github_token=${GITHUB_TOKEN:?GITHUB_TOKEN must not be empty}
  fi
elif [ "${tpe}" == "app" ]; then
  kubectl create secret generic controller-manager \
    -n actions-runner-system \
    --from-literal=github_app_id=${APP_ID:?must not be empty} \
    --from-literal=github_app_installation_id=${INSTALLATION_ID:?must not be empty} \
    --from-file=github_app_private_key=${PRIVATE_KEY_FILE_PATH:?must not be empty}
else
  echo "ACCEPTANCE_TEST_SECRET_TYPE must be set to either \"token\" or \"app\"" 1>&2
  exit 1
fi

tool=${ACCEPTANCE_TEST_DEPLOYMENT_TOOL}

if [ "${tool}" == "helm" ]; then
  helm upgrade --install actions-runner-controller \
    charts/actions-runner-controller \
    -n actions-runner-system \
    --create-namespace \
    --set syncPeriod=${SYNC_PERIOD} \
    --set authSecret.create=false \
    --set image.repository=${NAME} \
    --set image.tag=${VERSION} \
    -f ${VALUES_FILE}
  kubectl apply -f charts/actions-runner-controller/crds
  kubectl -n actions-runner-system wait deploy/actions-runner-controller --for condition=available --timeout 60s
else
  kubectl apply \
    -n actions-runner-system \
    -f release/actions-runner-controller.yaml
  kubectl -n actions-runner-system wait deploy/controller-manager --for condition=available --timeout 120s
fi

# Adhocly wait for some time until actions-runner-controller's admission webhook gets ready
sleep 20

RUNNER_LABEL=${RUNNER_LABEL:-self-hosted}

if [ -n "${TEST_REPO}" ]; then
  if [ "${USE_RUNNERSET}" -ne "false" ]; then
      cat acceptance/testdata/repo.runnerset.yaml | envsubst | kubectl apply -f -
      cat acceptance/testdata/repo.runnerset.hra.yaml | envsubst | kubectl apply -f -
  else
    echo 'Deploying runnerdeployment and hra. Set USE_RUNNERSET if you want to deploy runnerset instead.'
    cat acceptance/testdata/repo.runnerdeploy.yaml | envsubst | kubectl apply -f -
    cat acceptance/testdata/repo.hra.yaml | envsubst | kubectl apply -f -
  fi
else
  echo 'Skipped deploying runnerdeployment and hra. Set TEST_REPO to "yourorg/yourrepo" to deploy.'
fi

if [ -n "${TEST_ORG}" ]; then
  cat acceptance/testdata/runnerdeploy.envsubst.yaml | TEST_ENTERPRISE= TEST_REPO= NAME=org-runnerdeploy envsubst | kubectl apply -f -

  if [ -n "${TEST_ORG_GROUP}" ]; then
    cat acceptance/testdata/runnerdeploy.envsubst.yaml | TEST_ENTERPRISE= TEST_REPO= TEST_GROUP=${TEST_ORG_GROUP} NAME=orggroup-runnerdeploy envsubst | kubectl apply -f -
  else
    echo 'Skipped deploying enterprise runnerdeployment. Set TEST_ORG_GROUP to deploy.'
  fi
else
  echo 'Skipped deploying organizational runnerdeployment. Set TEST_ORG to deploy.'
fi

if [ -n "${TEST_ENTERPRISE}" ]; then
  cat acceptance/testdata/runnerdeploy.envsubst.yaml | TEST_ORG= TEST_REPO= NAME=enterprise-runnerdeploy envsubst | kubectl apply -f -

  if [ -n "${TEST_ENTERPRISE_GROUP}" ]; then
    cat acceptance/testdata/runnerdeploy.envsubst.yaml | TEST_ORG= TEST_REPO= TEST_GROUP=${TEST_ENTERPRISE_GROUP} NAME=enterprisegroup-runnerdeploy envsubst | kubectl apply -f -
  else
    echo 'Skipped deploying enterprise runnerdeployment. Set TEST_ENTERPRISE_GROUP to deploy.'
  fi
else
  echo 'Skipped deploying enterprise runnerdeployment. Set TEST_ENTERPRISE to deploy.'
fi
