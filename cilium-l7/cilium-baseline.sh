#!/bin/bash

# Remove existing clusters with this name
kind delete cluster --name no-kubeproxy-multinode

kind create cluster --config ./no-kubeproxy-multinode.yaml

helm repo add cilium https://helm.cilium.io/

helm install cilium -n kube-system cilium/cilium --version 1.16.1 \
--set debug.verbose=datapath \
--set l7Proxy=true \
--set kubeProxyReplacement=true \
--set k8sServiceHost="$(kubectl get endpoints kubernetes -n default -ojson | jq '.subsets[0].addresses[0].ip' -r)" \
--set k8sServicePort=6443 \
--set ipam.mode=kubernetes

kubectl wait --for=condition=ready pod --selector=k8s-app=cilium --timeout=120s -n kube-system

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/high-availability.yaml

kubectl patch -n kube-system deployment metrics-server --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl wait --for=condition=ready pod --selector=k8s-app=kube-dns --timeout=120s -n kube-system

# Fortio Server
kubectl apply -f ./fortio-server.yaml

kubectl wait --for=condition=ready pod --selector=app=fortio --timeout=120s


# Fortio Client
kubectl apply -f ./fortio-client.yaml

kubectl wait --for=condition=ready pod --selector=app=fortio-client --timeout=120s

# Tail logs and wait for the command to exit
# Copy that JSON and paste it into a file called "cilium-baseline.json"
kubectl logs -f "$(kubectl get pods -l app=fortio-client -ojson | jq -r '.items[0].metadata.name')"

# Now run the following command (locally) to spin up the fortio UI and view the report
# I develop in a devcontainer, so I download the json files to my local downloads folder
# and run the following command to spin up the fortio UI:
# docker run -v ~/Downloads:/var/lib/fortio:ro -p 8080:8080 -p 8079:8079 fortio/fortio report --data-dir=/var/lib/fortio
