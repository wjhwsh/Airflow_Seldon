
.PHONY: create_cluster
create_cluster:
	kind create cluster --name seldon
	kubectl create namespace seldon

.PHONY: delete_cluster
delete_cluster:
	kind delete cluster --name seldon

.PHONY: helm_setup
helm_setup:
	helm repo add seldonio https://storage.googleapis.com/seldon-charts
	helm repo update

# Install istio and patch nodePort to allow 8004 to point to ingress gateway
.PHONY: install_istio
install_istio:
	istioctl install --set profile=demo -y
	kubectl label namespace default istio-injection=enabled
	kubectl apply -f ./resources/istio_gateway.yaml

.PHONY: install_seldon
install_seldon:
	kubectl create namespace seldon-system || echo "namespace seldon-system exists"
	sleep 2
	helm delete seldon --namespace seldon-system || echo "seldon-core not installed"
	helm install seldon-core seldon-core-operator \
    --repo https://storage.googleapis.com/seldon-charts \
    --set usageMetrics.enabled=true \
    --set istio.enabled=true \
    --namespace seldon-system
	
.PHONY: setup
setup: create_cluster helm_setup install_istio install_seldon install_models port-forward-istio

.PHONY: port-forward-istio
port-forward-istio:
	kubectl port-forward -n istio-system svc/istio-ingressgateway 8081:80

.PHONY: install_models
install_models:
	kubectl wait --for=condition=Ready pods --all -n seldon-system
	kubectl apply -f ./resources/iris_model.yaml

.PHONE: test
test:
	curl -X POST http://localhost:8081/seldon/seldon/iris-model/api/v1.0/predictions \
	-H 'Content-Type: application/json' \
	-d '{ "data": { "ndarray": [[1,2,3,4]] } }'

.PHONE: help
help:
	@echo "make setup - setup seldon. make delete_cluster - delete cluster"
	@echo "make setup create_cluster delete_cluster helm_setup install_istio"
	@echo "make port-forward-istio test"
	
.DEFAULT_GOAL := help
