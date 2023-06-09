#!/bin/sh

# export VAULT_ADDR=http://127.0.0.1:8200
# aws eks update-kubeconfig --region us-east-1 --name $(terraform output -raw cluster_name) --alias=us-east-1

helm repo add stable https://charts.helm.sh/stable
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install my-nginx ingress-nginx/ingress-nginx \
    --set ingressClassResource.default=true \
    --set controller.watchIngressWithoutClass=true

kubectl apply -f pq_template/

kubectl wait --timeout=180s --for=condition=Ready $(kubectl get pod pq-postgresql-0 -o name)

helm install vault hashicorp/vault -f vault/values.yaml 
# kubectl apply -f vault_template

sleep 60

nohup kubectl port-forward service/vault 8200:8200 --pod-running-timeout=10m &

sleep 10s


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

######################
# Ci/CD
######################
cat ~/.kube/config | base64 | gh secret set KUBE_CONFIG


