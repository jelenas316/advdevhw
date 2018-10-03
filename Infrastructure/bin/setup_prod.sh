#!/bin/bash
# Setup Production Project (initial active services: Green)
if [ "$#" -ne 1 ]; then
    echo "Usage:"
    echo "  $0 GUID"
    exit 1
fi

GUID=$1
echo "Setting up Parks Production Environment in project ${GUID}-parks-prod"

# Code to set up the parks production project. It will need a StatefulSet MongoDB, and two applications each (Blue/Green) for NationalParks, MLBParks and Parksmap.
# The Green services/routes need to be active initially to guarantee a successful grading pipeline run.

# To be Implemented by Student
oc policy add-role-to-group system:image-puller system:serviceaccounts:${GUID}-parks-prod -n ${GUID}-parks-dev
oc policy add-role-to-user edit system:serviceaccount:${GUID}-jenkins:jenkins -n ${GUID}-parks-prod
oc policy add-role-to-user view --serviceaccount=default -n ${GUID}-parks-prod
oc policy add-role-to-user edit system:serviceaccount:gpte-jenkins:jenkins -n ${GUID}-parks-prod
oc policy add-role-to-user admin system:serviceaccount:gpte-jenkins:jenkins -n ${GUID}-parks-prod

echo 'kind: Service
apiVersion: v1
metadata:
  name: "mongodb-internal"
  labels:
    name: "mongodb"
  annotations:
    service.alpha.kubernetes.io/tolerate-unready-endpoints: "true"
spec:
  clusterIP: None
  ports:
    - name: mongodb
      port: 27017
  selector:
    name: "mongodb"' | oc create -n ${GUID}-parks-prod -f -

echo 'kind: Service
apiVersion: v1
metadata:
  name: "mongodb"
  labels:
    name: "mongodb"
spec:
  ports:
    - name: mongodb
      port: 27017
  selector:
    name: "mongodb"' | oc create -n ${GUID}-parks-prod -f -

oc create -f ./Infrastructure/templates/mogodb-prod.yaml -n ${GUID}-parks-prod

oc create configmap mlbparks-blue-config --from-env-file=./Infrastructure/templates/MLBParks-blue.env -n ${GUID}-parks-prod

oc create configmap nationalparks-blue-config --from-env-file=./Infrastructure/templates/NationalParks-blue.env -n ${GUID}-parks-prod

oc create configmap parksmap-blue-config --from-env-file=./Infrastructure/templates/ParksMap-blue.env -n ${GUID}-parks-prod

oc create configmap mlbparks-green-config --from-env-file=./Infrastructure/templates/MLBParks-green.env -n ${GUID}-parks-prod

oc create configmap nationalparks-green-config --from-env-file=./Infrastructure/templates/NationalParks-green.env -n ${GUID}-parks-prod

oc create configmap parksmap-green-config --from-env-file=./Infrastructure/templates/ParksMap-green.env -n ${GUID}-parks-prod


oc new-app ${GUID}-parks-dev/mlbparks:0.0 --name=mlbparks-blue --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod
oc new-app ${GUID}-parks-dev/nationalparks:0.0 --name=nationalparks-blue --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod
oc new-app ${GUID}-parks-dev/parksmap:0.0 --name=parksmap-blue --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod

oc set triggers dc/mlbparks-blue --remove-all -n ${GUID}-parks-prod

oc set triggers dc/nationalparks-blue --remove-all -n ${GUID}-parks-prod

oc set triggers dc/parksmap-blue --remove-all -n ${GUID}-parks-prod

oc set env dc/mlbparks-blue --from=configmap/mlbparks-blue-config -n ${GUID}-parks-prod

oc set env dc/nationalparks-blue --from=configmap/nationalparks-blue-config -n ${GUID}-parks-prod

oc set env dc/parksmap-blue --from=configmap/parksmap-blue-config -n ${GUID}-parks-prod



oc new-app ${GUID}-parks-dev/mlbparks:0.0 --name=mlbparks-green --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod
oc new-app ${GUID}-parks-dev/nationalparks:0.0 --name=nationalparks-green --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod
oc new-app ${GUID}-parks-dev/parksmap:0.0 --name=parksmap-green --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod

oc set triggers dc/mlbparks-green --remove-all -n ${GUID}-parks-prod

oc set triggers dc/nationalparks-green --remove-all -n ${GUID}-parks-prod

oc set triggers dc/parksmap-green --remove-all -n ${GUID}-parks-prod

oc set env dc/mlbparks-green --from=configmap/mlbparks-green-config -n ${GUID}-parks-prod

oc set env dc/nationalparks-green --from=configmap/nationalparks-green-config -n ${GUID}-parks-prod

oc set env dc/parksmap-green --from=configmap/parksmap-green-config -n ${GUID}-parks-prod


oc expose dc mlbparks-green --port 8080 -n ${GUID}-parks-prod

oc expose dc nationalparks-green --port 8080 -n ${GUID}-parks-prod

oc expose dc parksmap-green --port 8080 -n ${GUID}-parks-prod


oc expose dc mlbparks-blue --port 8080 -n ${GUID}-parks-prod

oc expose dc nationalparks-blue --port 8080 -n ${GUID}-parks-prod

oc expose dc parksmap-blue --port 8080 -n ${GUID}-parks-prod

oc expose svc mlbparks-green --name mlbparks -n ${GUID}-parks-prod --labels="type=parksmap-backend"

oc expose svc nationalparks-green --name nationalparks -n ${GUID}-parks-prod --labels="type=parksmap-backend"

oc expose svc parksmap-green --name parksmap -n ${GUID}-parks-prod

oc set deployment-hook dc/nationalparks-green  -n ${GUID}-parks-prod --post -c nationalparks-green --failure-policy=ignore -- curl http://nationalparks-green${GUID}-parks-prod.svc.cluster.local:8080/ws/data/load/
oc set deployment-hook dc/mlbparks-green  -n ${GUID}-parks-prod --post -c mlbparks-green --failure-policy=ignore -- curl http://mlbparks-green.${GUID}-parks-prod.svc.cluster.local:8080/ws/data/load/

oc set deployment-hook dc/nationalparks-blue  -n ${GUID}-parks-prod --post -c nationalparks-blue --failure-policy=ignore -- curl http://nationalparks-blue.${GUID}-parks-prod.svc.cluster.local:8080/ws/data/load/
oc set deployment-hook dc/mlbparks-blue  -n ${GUID}-parks-prod --post -c mlbparks-blue --failure-policy=ignore -- curl http://mlbparks-blue.${GUID}-parks-prod.svc.cluster.local:8080/ws/data/load/
