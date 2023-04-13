#!/bin/sh

# This script is used to setup the both Vault servers (East & West) in the demo environment.

aws eks update-kubeconfig --region us-east-1 --name $(terraform output -raw cluster_name)

export AWS_REGION=us-east-1
kubectl delete secret vault
kubectl create secret generic vault \
  --from-file=license=vault.hclic

helm install vault hashicorp/vault -f values.yaml

nohup kubectl port-forward service/vault-ui 8200:8200 --pod-running-timeout=10m &

kubectl wait --timeout=60s --for=condition=Ready $(kubectl get pod vault-0 -o name)

vault login root
vault secrets enable -path=east kv-v2



sleep 10s





aws eks update-kubeconfig --region us-west-1 --name $(terraform output -raw cluster_name_west)

export AWS_REGION=us-west-1
kubectl delete secret vault
kubectl create secret generic vault \
  --from-file=license=vault.hclic

helm install vault hashicorp/vault -f values.yaml

vault login root
vault secrets enable -path=east kv-v2

nohup kubectl port-forward service/vault-ui 8400:8200 --pod-running-timeout=10m &


kubectl run mycurlpod --image=curlimages/curl -i --tty -- sh
