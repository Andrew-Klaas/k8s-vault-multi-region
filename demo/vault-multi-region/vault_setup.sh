#!/bin/sh

# This script is used to setup the both Vault servers (East & West) in the demo environment.
rm ~/.kube/config

aws eks update-kubeconfig --region us-east-1 --name $(terraform output -raw cluster_name) --alias=us-east-1
alias ke="kubectl config use-context us-east-1; kubectl"
export AWS_REGION=us-east-1
helm delete vault
kubectl delete svc vault-ui
kubectl delete pvc data-vault-0
kubectl delete pvc data-vault-1
kubectl delete pvc data-vault-2
kubectl delete secret vault
kubectl create secret generic vault \
  --from-file=license=demo/vault-multi-region/vault.hclic
helm install vault hashicorp/vault -f demo/vault-multi-region/values.yaml

sleep 60

kubectl apply -f cluster_addr_service.yaml
nohup kubectl port-forward service/vault-ui 8200:8200 --pod-running-timeout=10m &
kubectl exec -it vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > keys-east.json
kubectl exec -it vault-0 -- vault operator unseal $(jq -r ".unseal_keys_b64[]" keys-east.json)
kubectl exec -it vault-0 -- vault login $(jq -r ".root_token" keys-east.json) -format=json > .vault_token
kubectl exec -it vault-0 -- env VAULT_TOKEN="$(jq -r ".auth.client_token" .vault_token)" vault secrets enable -path=east kv-v2

export VAULT_TOKEN=$(jq -r ".root_token" keys-east.json)
export VAULT_ADDR=http://localhost:8200
echo 'path "*" {
    capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}' | vault policy write vault_admin -
vault auth enable userpass
vault write auth/userpass/users/vault password=vault policies=vault_admin

jq -r ".root_token" keys-east.json

sleep 10

alias vault2="VAULT_ADDR=http://localhost:8400 vault"
aws eks update-kubeconfig --region us-west-1 --name $(terraform output -raw cluster_name_west) --alias=us-west-1
alias kw="kubectl config use-context us-west-1; kubectl"
export AWS_REGION=us-west-1
helm delete vault
kubectl delete svc vault-ui
kubectl delete pvc data-vault-0
kubectl delete pvc data-vault-1
kubectl delete pvc data-vault-2
kubectl delete secret vault
kubectl create secret generic vault \
  --from-file=license=demo/vault-multi-region/vault.hclic
helm install vault hashicorp/vault -f demo/vault-multi-region/values.yaml

sleep 60
kubectl apply -f cluster_addr_service.yaml

nohup kubectl port-forward service/vault-ui 8400:8200 --pod-running-timeout=10m &
kw exec -it vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > keys-west.json
kw exec -it vault-0 -- vault operator unseal $(jq -r ".unseal_keys_b64[]" keys-west.json)
kw exec -it vault-0 -- vault login $(jq -r ".root_token" keys-west.json) -format=json > .vault_token_west
kw exec -it vault-0 -- env VAULT_TOKEN="$(jq -r ".auth.client_token" .vault_token_west)" vault secrets enable -path=west kv-v2

export VAULT_TOKEN=$(jq -r ".root_token" keys-west.json)
export VAULT_ADDR=http://localhost:8400
echo 'path "*" {
    capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}' | vault2 policy write vault_admin -
vault2 auth enable userpass
vault2 write auth/userpass/users/vault password=vault policies=vault_admin



jq -r ".root_token" keys-east.json

##############
# Replication
##############
sleep 30

#enable replication on the primary
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(jq -r ".root_token" keys-east.json)
alias ke="kubectl config use-context us-east-1; kubectl"
ke get svc vault-cluster-addr -o json > vault_east_svc.json
ke get svc vault-ui -o json > vault_east_api_svc.json

primary_cluster_addr=$(jq -r ".status.loadBalancer.ingress[0].hostname" vault_east_svc.json)
primary_api_addr=$(jq -r ".status.loadBalancer.ingress[0].hostname" vault_east_api_svc.json)

vault write -f sys/replication/performance/primary/enable primary_cluster_addr="https://$primary_cluster_addr:8201"
vault write sys/replication/performance/primary/secondary-token id=west -format=json > .vault_replication_token

#Get the West loadbalancer service
alias kw="kubectl config use-context us-west-1; kubectl"
#enable replication on the secondary
export VAULT_TOKEN=$(jq -r ".root_token" keys-west.json)
export VAULT_ADDR=http://localhost:8400
vault2 write sys/replication/performance/secondary/enable \
  token="$(jq -r ".wrap_info.token" .vault_replication_token)" \
  primary_api_addr="http://$primary_api_addr:8200"


exit 0


kubectl run mycurlpod --image=curlimages/curl -i --tty -- sh

aws eks update-kubeconfig --region us-east-1 --name $(terraform output -raw cluster_name) --alias=us-east-1
nohup kubectl port-forward service/vault-ui 8200:8200 --pod-running-timeout=10m &


aws eks update-kubeconfig --region us-west-1 --name $(terraform output -raw cluster_name_west) --alias=us-west-1
nohup kubectl port-forward service/vault-ui 8400:8200 --pod-running-timeout=10m &


ke get svc vault-cluster-addr
kw get svc vault-cluster-addr