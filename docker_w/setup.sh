!#/bin/bash

echo "$1"

kubectl create clusterrolebinding permissive-binding \
  --clusterrole=cluster-admin \
  --user=admin \
  --user=kubelet \
  --group=system:serviceaccounts

# kubectl create secret generic mongodb \
#    --from-literal=connstring="mongodb://UserAdmin:password@3.95.207.234:27017" 

kubectl create secret generic mongodb \
   --from-literal=connstring="mongodb://UserAdmin:password@$1:27017" 


#SHOW APP WRITING TO DATABASE
# https://stackoverflow.com/questions/24985684/mongodb-show-all-contents-from-all-collections
# db.getCollectionNames().forEach(c => {
#     db[c].find().forEach(d => {
#         print(c); 
#         printjson(d)
#     })
# })


#SHOW ADMIN PRIVILEDGED CONTAINER POD
#https://kubernetes.io/docs/tasks/run-application/access-api-from-pod/#:~:text=When%20accessing%20the%20API%20from,the%20API%20server%20and%20authenticate.
# Point to the internal API server hostname
# APISERVER=https://kubernetes.default.svc

# # Path to ServiceAccount token
# SERVICEACCOUNT=/var/run/secrets/kubernetes.io/serviceaccount

# # Read this Pod's namespace
# NAMESPACE=$(cat ${SERVICEACCOUNT}/namespace)

# # Read the ServiceAccount bearer token
# TOKEN=$(cat ${SERVICEACCOUNT}/token)

# # Reference the internal certificate authority (CA)
# CACERT=${SERVICEACCOUNT}/ca.crt

# # Explore the API with TOKEN
# curl --cacert ${CACERT} --header "Authorization: Bearer ${TOKEN}" -X GET ${APISERVER}/api

curl --cacert ${CACERT} --header "Authorization: Bearer ${TOKEN}" -X GET ${APISERVER}/api/v1/namespaces/default/secrets