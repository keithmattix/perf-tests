#!/bin/bash

# Remove existing clusters with this name
kind delete cluster --name no-kubeproxy-multinode

kind create cluster --config ../no-kubeproxy-multinode.yaml

helm repo add cilium https://helm.cilium.io/

helm install cilium -n kube-system cilium/cilium --version 1.16.1 \
--set debug.verbose=datapath \
--set kubeProxyReplacement=true \
--set k8sServiceHost="$(kubectl get endpoints kubernetes -n default -ojson | jq '.subsets[0].addresses[0].ip' -r)" \
--set k8sServicePort=6443 \
--set ipam.mode=kubernetes

kubectl wait --for=condition=ready pod --selector=k8s-app=cilium --timeout=120s -n kube-system

# Add gateway API CRDs
kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || { kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml; }

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/high-availability.yaml

kubectl patch -n kube-system deployment metrics-server --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl wait --for=condition=ready pod --selector=k8s-app=kube-dns --timeout=120s -n kube-system

# Install Istio Ambient
istioctl install --set profile=ambient --set tag=1.23.0 --set hub=docker.io/istio --revision=1-23-0 --set values.defaultRevision=1-23-0 -y

kubectl wait --for=condition=ready pod --selector=app=istiod --timeout=120s -n istio-system
kubectl wait --for=condition=ready pod --selector=app=ztunnel --timeout=120s -n istio-system

# Fortio Server
kubectl apply -f ../fortio-server.yaml

kubectl wait --for=condition=ready pod --selector=app=fortio --timeout=120s

# Add the default namespace to the mesh (including the already running server)
kubectl label namespace default istio.io/dataplane-mode=ambient

# Fortio Client
kubectl apply -f ../fortio-client.yaml

kubectl wait --for=condition=ready pod --selector=app=fortio-client --timeout=120s

# Tail logs until the pod exits
# Copy that JSON and paste it into a file called "cilium-l7.json"
kubectl logs -f "$(kubectl get pods -l app=fortio-client -ojson | jq -r '.items[0].metadata.name')"

# Now run the following command (locally) to spin up the fortio UI and view the report
# I develop in a devcontainer, so I download the json files to my local downloads folder
# and run the following command to spin up the fortio UI:
# docker run -v ~/Downloads:/var/lib/fortio:ro -p 8080:8080 -p 8079:8079 fortio/fortio report --data-dir=/var/lib/fortio
