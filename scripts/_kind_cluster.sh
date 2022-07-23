#!/usr/bin/env bash
set -eo pipefail

if [[ $(uname -s) != "Darwin" ]]; then
    set -u
fi
export SELDON_API_PORT=${SELDON_API_PORT:="8081"}
export SELDON_SYSTEM_NAMESPACE=${SELDON_SYSTEM_NAMESPACE:="seldon-system"}
export SELDON_MODEL_NAMESPACE=${SELDON_MODEL_NAMESPACE:="seldon"}
export SELDON_MODEL_YAML=${SELDON_MODEL_YAML:="iris-model.yaml"}
export ISTIO_YAML=${ISTIO_YAML:="istio.yaml"}

export KIND_CLUSTER_NAME=${SELDON_CLUSTER_NAME:="seldon"}
# Name of the KinD cluster to connect to when referred to via kubectl
export KUBECTL_CLUSTER_NAME=kind-${KIND_CLUSTER_NAME}
readonly KUBECTL_CLUSTER_NAME
export CURRENT_FOLDER="$( dirname "${BASH_SOURCE[0]}")"

function kind::create_cluster() {
    kind create cluster \
            --name "${KIND_CLUSTER_NAME}" --wait 2m
    echo
    echo "Created cluster ${KIND_CLUSTER_NAME}"
    echo
    kubectl cluster-info --context "${KUBECTL_CLUSTER_NAME}"
}

function kind::install_istio() {
    if ! command -v istioctl &> /dev/null
    then
    echo
    echo "istioctl could not be found"
    echo "Run following command to install istioctl"
    echo "cd ~"
    echo "curl -L https://istio.io/downloadIstio | sh -"
    echo "cd istio-1.11.4"
    echo "export PATH=$PWD/bin:$PATH"
    echo
    exit
    fi
    istioctl install --set profile=demo -y
    kubectl label namespace default istio-injection=enabled
    kubectl apply -f "${CURRENT_FOLDER}/${ISTIO_YAML}"
}

function kind::install_seldon() {
    kubectl create namespace "${SELDON_SYSTEM_NAMESPACE}"
    helm install seldon-core seldon-core-operator \
    --repo "https://storage.googleapis.com/seldon-charts" \
    --set "usageMetrics.enabled=true" \
    --set "istio.enabled=true" \
    --namespace "${SELDON_SYSTEM_NAMESPACE}" \
    --wait

    kubectl get pods -n "${SELDON_SYSTEM_NAMESPACE}"
    # #kubectl wait --for=jsonpath='{.status.phase}'=Running pod/busybox1 --timeout=60s
    #kubectl port-forward -n istio-system svc/istio-ingressgateway "${SELDON_API_PORT}":80
    
    # #kubectl wait --for=jsonpath='{.status.phase}'=Running pod/busybox1 --timeout=60s
}
function kind::port-forward() {
    kubectl port-forward -n istio-system svc/istio-ingressgateway "${SELDON_API_PORT}":80
}

function kind::apply_iris_model() {
    kubectl create namespace "${SELDON_MODEL_NAMESPACE}"
    kubectl apply -f "${SELDON_MODEL_YAML}"
}

function kind::check_model_deployment() {
    curl -X POST "http://localhost:${SELDON_API_PORT}/seldon/seldon/iris-model/api/v1.0/predictions" \
    -H 'Content-Type: application/json' \
    -d '{ "data": { "ndarray": [[1,2,3,4]] } }'
}

function kind::delete_cluster() {
    kind delete cluster --name "${KIND_CLUSTER_NAME}"
    echo
    echo "Deleted cluster ${KIND_CLUSTER_NAME}"
    echo
}

MAX_NUM_TRIES_FOR_MODEL_CHECK=12
readonly MAX_NUM_TRIES_FOR_MODEL_CHECK

SLEEP_TIME_FOR_MODEL_CHECK=10
readonly SLEEP_TIME_FOR_MODEL_CHECK

function kind::wait_for_model_deployment_ready() {
    num_tries=0
    set +e
    sleep "${SLEEP_TIME_FOR_MODEL_CHECK}"
    while ! curl --connect-timeout 60  --max-time 60 -X POST \
    "http://localhost:${SELDON_API_PORT}/seldon/seldon/iris-model/api/v1.0/predictions" \
        -H 'Content-Type: application/json' \
        -d '{ "data": { "ndarray": [[1,2,3,4]] } }' \
        -s | grep -q data; do
        echo
        echo "Sleeping ${SLEEP_TIME_FOR_MODEL_CHECK} while waiting for model deployment being ready"
        echo
        sleep "${SLEEP_TIME_FOR_MODEL_CHECK}"
        num_tries=$((num_tries + 1))
        if [[ ${num_tries} == "${MAX_NUM_TRIES_FOR_MODEL_CHECK}" ]]; then
            echo
            echo  "${COLOR_RED}ERROR: Timeout while waiting for the model deployment check  ${COLOR_RESET}"
            echo
            return 1
        fi
    done
    echo
    echo "Connection to 'seldon model server' established on port ${SELDON_API_PORT}"
    echo
    set -e
}

function kind::perform_kind_cluster_operation() {
    ALLOWED_KIND_OPERATIONS="[ start recreate stop test]"
    readonly ALLOWED_KIND_OPERATIONS
    set +u
    if [[ -z "$1" ]]; then
        echo
        echo  "${COLOR_RED}ERROR: Operation must be provided as first parameter. One of: ${ALLOWED_KIND_OPERATIONS}  ${COLOR_RESET}"
        echo
        exit 1
    fi

    set -u
    local operation="${1}"
    local all_clusters
    all_clusters=$(kind get clusters || true)

    if [[ ${operation} == "status" ]]; then
        if [[ ${all_clusters} == *"${KIND_CLUSTER_NAME}"* ]]; then
            echo
            echo "Cluster name: ${KIND_CLUSTER_NAME}"
            echo
            kind::check_cluster_ready_for_airflow
            echo
            exit
        else
            echo
            echo "Cluster ${KIND_CLUSTER_NAME} is not running"
            echo
            exit
        fi
    fi
    if [[ ${all_clusters} == *"${KIND_CLUSTER_NAME}"* ]]; then
        if [[ ${operation} == "start" ]]; then
            echo
            echo "Cluster ${KIND_CLUSTER_NAME} is already created"
            echo "Reusing previously created cluster"
            echo
        elif [[ ${operation} == "recreate" ]]; then
            echo
            echo "Recreating cluster"
            echo
            kind::delete_cluster
            kind::create_cluster
            kind::install_istio
            kind::install_seldon
            kind::apply_iris_model
            kind::port-forward

        elif [[ ${operation} == "stop" ]]; then
            echo
            echo "Deleting cluster"
            echo
            kind::delete_cluster
            exit
        elif [[ ${operation} == "test" ]]; then
            echo
            echo "Checking iris model"
            echo
            kind::check_model_deployment
        else
            echo
            echo  "${COLOR_RED}ERROR: Wrong cluster operation: ${operation}. Should be one of: ${ALLOWED_KIND_OPERATIONS}  ${COLOR_RESET}"
            echo
            exit 1
        fi
    else
        if [[ ${operation} == "start" || ${operation} == "recreate" ]]; then
            echo
            echo "Creating cluster"
            echo
            kind::create_cluster
            kind::install_istio
            kind::install_seldon
            kind::apply_iris_model
            kind::port-forward
        
        elif [[ ${operation} == "stop" || ${operation} == "test" ]]; then
            echo
            echo  "${COLOR_RED}ERROR: Cluster ${KIND_CLUSTER_NAME} does not exist. It should exist for ${operation} operation  ${COLOR_RESET}"
            echo
            exit 1
        else
            echo
            echo  "${COLOR_RED}ERROR: Wrong cluster operation: ${operation}. Should be one of ${ALLOWED_KIND_OPERATIONS}  ${COLOR_RESET}"
            echo
            exit 1
        fi
    fi
}


