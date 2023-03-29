#!/bin/bash

kubectl delete -f go_vault_demo
kubectl delete -f pq_template
kubectl delete -f vault_template
helm delete consul

kubectl delete -f consul/gateway-configuration.yaml
kubectl delete svc ingress-gateway

kubectl delete pvc data-default-consul-server-0
kubectl delete pvc data-default-consul-server-1
kubectl delete pvc data-default-consul-server-2
kubectl delete pvc data-pq-postgresql-0