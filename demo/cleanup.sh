#!/bin/bash

kubectl delete -f new_vault-go-demo
kubectl delete -f pq_template
kubectl delete -f vault_template
# helm delete consul
helm delete vault

# kubectl delete pvc data-default-consul-server-0
# kubectl delete pvc data-default-consul-server-1
# kubectl delete pvc data-default-consul-server-2
kubectl delete pvc data-pq-postgresql-0