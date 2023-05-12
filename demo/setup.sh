#!/bin/sh
# cd ../
# aws eks --region $(terraform output -raw region) update-kubeconfig --name $(terraform output -raw cluster_name)
# cd demo/

aws eks update-kubeconfig --region us-east-1 --name $(terraform output -raw cluster_name) --alias=us-east-1
alias ke="kubectl config use-context us-east-1; kubectl"

helm repo add stable https://charts.helm.sh/stable
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update



helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install my-nginx ingress-nginx/ingress-nginx



# helm search repo hashicorp/consul
# kubectl apply --kustomize "github.com/hashicorp/consul-api-gateway/config/crd?ref=v0.1.0"
# helm install consul hashicorp/consul -f consul/new.values.yaml
# k apply -f consul/gateway-configuration.yaml

# kubectl wait --timeout=180s --for=condition=Ready $(kubectl get pod --selector=app=consul -o name)
# sleep 1s
# cat <<EOF | kubectl apply -f -
# apiVersion: v1
# kind: ConfigMap
# metadata:
#   labels:
#     addonmanager.kubernetes.io/mode: EnsureExists
#   name: kube-dns
#   namespace: kube-system
# data:
#   stubDomains: |
#     {"consul": ["$(kubectl get svc consul-dns -o jsonpath='{.spec.clusterIP}')"]}
# EOF

# helm install pq \
#   --set auth.database=vault_go_demo,auth.postgresPassword=MySecretPassW0rd \
#     bitnami/postgresql --version 11.0.2
# ➜  eks helm template pq \
#   --set auth.database=vault_go_demo,auth.postgresPassword=MySecretPassW0rd \
#     bitnami/postgresql --version 11.0.2 > pq_template.yaml

kubectl apply -f pq_template/

kubectl wait --timeout=180s --for=condition=Ready $(kubectl get pod pq-postgresql-0 -o name)

helm install vault hashicorp/vault -f vault/values.yaml 
# kubectl apply -f vault_template

sleep 60

nohup kubectl port-forward service/vault 8200:8200 --pod-running-timeout=10m &

sleep 5s

export VAULT_ADDR=http://127.0.0.1:8200

vault login root

cat << EOF > transit-app-example.policy
path "*" {
    capabilities = ["create", "read", "list", "sudo", "update", "delete"]
}
path "transit/*" {
    capabilities = ["create", "read", "list", "sudo", "update", "delete"]
}
EOF
vault policy write transit-app-example transit-app-example.policy

kubectl create serviceaccount vault-auth
kubectl apply --filename vault/vault-auth-service-account.yaml

export VAULT_SA_NAME=$(kubectl get sa vault-auth -o jsonpath="{.secrets[*]['name']}" | awk '{ print $1 }')
export SA_JWT_TOKEN=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data.token}" | base64 --decode; echo)
export SA_CA_CRT=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data['ca\.crt']}" | base64 --decode; echo)


export VAULT_ADDR=http://127.0.0.1:8200
export K8S_HOST="https://kubernetes.default.svc:443"
vault auth enable kubernetes

vault write auth/kubernetes/config \
        token_reviewer_jwt="$SA_JWT_TOKEN" \
        kubernetes_host="$K8S_HOST" \
        kubernetes_ca_cert="$SA_CA_CRT"

vault write auth/kubernetes/role/example \
        bound_service_account_names="*" \
        bound_service_account_namespaces="*" \
        policies=transit-app-example \
        ttl=72h

vault write auth/kubernetes/role/vault_go_demo \
        bound_service_account_names="*" \
        bound_service_account_namespaces="*" \
        policies=transit-app-example \
        ttl=72h

vault secrets enable database

vault write database/config/my-postgresql-database \
    plugin_name=postgresql-database-plugin \
    allowed_roles="my-role, vault_go_demo" \
    connection_url="postgresql://{{username}}:{{password}}@pq-postgresql.default.svc.cluster.local:5432/vault_go_demo?sslmode=disable" \
    username="postgres" \
    password="MySecretPassW0rd"

vault write database/roles/vault_go_demo \
    db_name=my-postgresql-database \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    ALTER USER \"{{name}}\" WITH SUPERUSER;" \
    default_ttl="1h" \
    max_ttl="24h"

vault read database/creds/vault_go_demo


vault secrets enable transit
vault write -f transit/keys/my-key

#Set your google oauth2 app client_id and client_secret as env variables
vault kv put secret/oauth2/config \
    client_id=$CLIENT_ID \
    client_secret=$CLIENT_SECRET


kubectl apply -f new_vault-go-demo/


exit 0








#######################
#### MULTI REGION DEMO
#######################

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

