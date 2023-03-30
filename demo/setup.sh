#!/bin/sh


#TODO CONSUL
# Routing/Splitting/Resolving
# L7 Intentions
# Metrics & Telemetry & Tracing & prometheus/grafana


# cd ../
# aws eks --region $(terraform output -raw region) update-kubeconfig --name $(terraform output -raw cluster_name)
# cd demo/

helm repo add stable https://charts.helm.sh/stable
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm search repo hashicorp/consul
kubectl apply --kustomize "github.com/hashicorp/consul-api-gateway/config/crd?ref=v0.1.0"
helm install consul hashicorp/consul -f consul/new.values.yaml

k apply -f consul/gateway-configuration.yaml

kubectl wait --timeout=180s --for=condition=Ready $(kubectl get pod --selector=app=consul -o name)
sleep 1s
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  labels:
    addonmanager.kubernetes.io/mode: EnsureExists
  name: kube-dns
  namespace: kube-system
data:
  stubDomains: |
    {"consul": ["$(kubectl get svc consul-dns -o jsonpath='{.spec.clusterIP}')"]}
EOF

# helm install pq \
#   --set auth.database=vault_go_demo,auth.postgresPassword=MySecretPassW0rd \
#     bitnami/postgresql --version 11.0.2
# ➜  eks helm template pq \
#   --set auth.database=vault_go_demo,auth.postgresPassword=MySecretPassW0rd \
#     bitnami/postgresql --version 11.0.2 > pq_template.yaml
kubectl apply -f pq_template/

kubectl wait --timeout=180s --for=condition=Ready $(kubectl get pod pq-postgresql-0 -o name)

helm install vault hashicorp/vault -f vault/values.yaml 
kubectl apply -f vault_template

sleep 60

nohup kubectl port-forward service/vault 8200:8200 --pod-running-timeout=10m &
nohup kubectl port-forward service/consul-ui 8500:80 --pod-running-timeout=10m &

sleep 5s

export VAULT_ADDR=http://127.0.0.1:8200
export CONSUL_ADDR=http://127.0.0.1:8500

vault login root

cat << EOF > transform-app-example.policy
path "*" {
    capabilities = ["read", "list", "create", "update", "delete"]
}
path "transit/*" {
    capabilities = ["read", "list", "create", "update", "delete"]
}
EOF
vault policy write transform-app-example transform-app-example.policy

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
        bound_service_account_names=vault-auth \
        bound_service_account_namespaces=default \
        policies=transform-app-example \
        ttl=72h

vault write auth/kubernetes/role/vault_go_demo \
        bound_service_account_names=vault-auth \
        bound_service_account_namespaces=default \
        policies=transform-app-example \
        ttl=72h

#go-movies-app
vault write auth/kubernetes/role/go-movies-app \
        bound_service_account_names=vault-auth \
        bound_service_account_namespaces=default \
        policies=transform-app-example \
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


kubectl apply -f go_vault_demo/


exit 0

kubectl exec -ti vault-0 -- vault operator init
kubectl exec -ti vault-0 -- vault operator unseal

kubectl exec -ti vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -ti vault-1 -- vault operator unseal

kubectl exec -ti vault-2 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -ti vault-2 -- vault operator unseal


Unseal Key 1: /eK7ujYQnChM/iAEG4EvOZ4TVRKuPysFNF99EyD0ViV5
Unseal Key 2: mCsJC9J1j85tRHlTxq4zx94UtKVAfQx19G/tId1IYcfH
Unseal Key 3: 4SSJPbvcgvEaI3nyX4f5NqJWiB54NHpZX9Mq5pzxo/rK
Unseal Key 4: 4eLWH3EXtdjvgzopRPxWvfIQlTlrNd1Jcthj7i3obpnI
Unseal Key 5: 0JAJgsG8IV92ZA0aninpwjpoHntXAOe64609J/sDt7LO

Initial Root Token: hvs.Xw2d971IS1LmBmLaRwAmCbYt

