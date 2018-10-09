#!/bin/bash
# Setup Production Project (initial active services: Green)
if [ "$#" -ne 1 ]; then
    echo "Usage:"
    echo "  $0 GUID"
    exit 1
fi
#echo "Skipping production for now"
#exit
#sleep 2000
#echo '....sleep 2000'

GUID=$1
echo "Setting up Parks Production Environment in project ${GUID}-parks-prod"

# Code to set up the parks production project. It will need a StatefulSet MongoDB, and two applications each (Blue/Green) for NationalParks, MLBParks and Parksmap.
# The Green services/routes need to be active initially to guarantee a successful grading pipeline run.

sleep 300

####     Grant the correct permissions to the Jenkins service account

####     Grant the correct permissions to pull images from the development project

####     Grant the correct permissions for the ParksMap application to read back-end services (see the associated README file)

#oc new-project $GUID-parks-prod --display-name "Shared Parks Prod"
oc project $GUID-parks-prod 
oc policy add-role-to-user view --serviceaccount=default -n $GUID-parks-prod
oc policy add-role-to-group system:image-puller system:serviceaccounts:$GUID-parks-prod -n $GUID-parks-dev
oc policy add-role-to-user edit system:serviceaccount:$GUID-jenkins:jenkins -n $GUID-parks-prod
oc policy add-role-to-user admin system:serviceaccount:gpte-jenkins:jenkins -n $GUID-parks-prod


echo 'MONGODB creation for prod'


oc create -f ./Infrastructure/templates/mongodb-prod.yml -n ${GUID}-parks-prod

while : ; do
    oc get pod -n ${GUID}-parks-prod | grep -v deploy | grep "1/1"
    echo "Checking if MongoDB is Ready..."
    if [ $? == "1" ] 
      then 
      echo "Wait 10 seconds..."
        sleep 10
      else 
        break 
    fi
done


echo '*********************************************************************************'
echo 'Rollout started'
echo '*********************************************************************************'


echo 'Create Prod configmaps'

oc create configmap mlbparks-blue-config --from-env-file=./Infrastructure/templates/b-MLBParks -n ${GUID}-parks-prod
oc create configmap nationalparks-blue-config --from-env-file=./Infrastructure/templates/b-NationalParks -n ${GUID}-parks-prod
oc create configmap parksmap-blue-config --from-env-file=./Infrastructure/templates/b-ParksMap -n ${GUID}-parks-prod
oc create configmap mlbparks-green-config --from-env-file=./Infrastructure/templates/g-MLBParks -n ${GUID}-parks-prod
oc create configmap nationalparks-green-config --from-env-file=./Infrastructure/templates/g-NationalParks -n ${GUID}-parks-prod
oc create configmap parksmap-green-config --from-env-file=./Infrastructure/templates/g-ParksMap -n ${GUID}-parks-prod


echo 'Create Blue apps'

oc new-app ${GUID}-parks-dev/mlbparks:0.0 --name=mlbparks-blue --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod
oc new-app ${GUID}-parks-dev/nationalparks:0.0 --name=nationalparks-blue --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod
oc new-app ${GUID}-parks-dev/parksmap:0.0 --name=parksmap-blue --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod

oc set triggers dc/mlbparks-blue --remove-all -n ${GUID}-parks-prod
oc set triggers dc/nationalparks-blue --remove-all -n ${GUID}-parks-prod
oc set triggers dc/parksmap-blue --remove-all -n ${GUID}-parks-prod


echo 'Set blue apps env'


oc set env dc/mlbparks-blue --from=configmap/mlbparks-blue-config -n ${GUID}-parks-prod
oc set env dc/nationalparks-blue --from=configmap/nationalparks-blue-config -n ${GUID}-parks-prod
oc set env dc/parksmap-blue --from=configmap/parksmap-blue-config -n ${GUID}-parks-prod


echo 'Set green apps'

oc new-app ${GUID}-parks-dev/mlbparks:0.0 --name=mlbparks-green --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod
oc new-app ${GUID}-parks-dev/nationalparks:0.0 --name=nationalparks-green --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod
oc new-app ${GUID}-parks-dev/parksmap:0.0 --name=parksmap-green --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod


echo 'Set triggers and env for green apps'

oc set triggers dc/mlbparks-green --remove-all -n ${GUID}-parks-prod
oc set triggers dc/nationalparks-green --remove-all -n ${GUID}-parks-prod
oc set triggers dc/parksmap-green --remove-all -n ${GUID}-parks-prod

oc set env dc/mlbparks-green --from=configmap/mlbparks-green-config -n ${GUID}-parks-prod
oc set env dc/nationalparks-green --from=configmap/nationalparks-green-config -n ${GUID}-parks-prod
oc set env dc/parksmap-green --from=configmap/parksmap-green-config -n ${GUID}-parks-prod

echo 'Expose dcs'

oc expose dc mlbparks-green --port 8080 -n ${GUID}-parks-prod
oc expose dc nationalparks-green --port 8080 -n ${GUID}-parks-prod
oc expose dc parksmap-green --port 8080 -n ${GUID}-parks-prod

oc expose dc mlbparks-blue --port 8080 -n ${GUID}-parks-prod
oc expose dc nationalparks-blue --port 8080 -n ${GUID}-parks-prod
oc expose dc parksmap-blue --port 8080 -n ${GUID}-parks-prod

echo 'Expose svc'

oc expose svc mlbparks-green --name mlbparks -n ${GUID}-parks-prod --labels="type=parksmap-backend"
oc expose svc nationalparks-green --name nationalparks -n ${GUID}-parks-prod --labels="type=parksmap-backend"
oc expose svc parksmap-green --name parksmap -n ${GUID}-parks-prod


echo 'Set deployment hooks'

oc set deployment-hook dc/mlbparks-green  -n ${GUID}-parks-prod --post -c mlbparks-green --failure-policy=ignore -- curl http://mlbparks-green.${GUID}-parks-prod.svc.cluster.local:8080/ws/data/load/
oc set deployment-hook dc/nationalparks-green  -n ${GUID}-parks-prod --post -c nationalparks-green --failure-policy=ignore -- curl http://nationalparks-green.${GUID}-parks-prod.svc.cluster.local:8080/ws/data/load/

oc set deployment-hook dc/mlbparks-blue  -n ${GUID}-parks-prod --post -c mlbparks-blue --failure-policy=ignore -- curl http://mlbparks-blue.${GUID}-parks-prod.svc.cluster.local:8080/ws/data/load/
oc set deployment-hook dc/nationalparks-blue  -n ${GUID}-parks-prod --post -c nationalparks-blue --failure-policy=ignore -- curl http://nationalparks-blue.${GUID}-parks-prod.svc.cluster.local:8080/ws/data/load/


echo 'Set probes'


oc set probe dc/parksmap-blue --liveness --failure-threshold 5 --initial-delay-seconds 30 -- echo ok -n ${GUID}-parks-prod
oc set probe dc/parksmap-blue --readiness --failure-threshold 5 --initial-delay-seconds 60 --get-url=http://:8080/ws/healthz/ -n ${GUID}-parks-prod
oc set probe dc/mlbparks-blue --liveness --failure-threshold 5 --initial-delay-seconds 30 -- echo ok -n ${GUID}-parks-prod
oc set probe dc/mlbparks-blue --readiness --failure-threshold 3 --initial-delay-seconds 60 --get-url=http://:8080/ws/healthz/ -n ${GUID}-parks-prod
oc set probe dc/nationalparks-blue --liveness --failure-threshold 5 --initial-delay-seconds 30 -- echo ok -n ${GUID}-parks-prod
oc set probe dc/nationalparks-blue --readiness --failure-threshold 3 --initial-delay-seconds 60 --get-url=http://:8080/ws/healthz/ -n ${GUID}-parks-prod
oc set probe dc/parksmap-green --liveness --failure-threshold 5 --initial-delay-seconds 30 -- echo ok -n ${GUID}-parks-prod
oc set probe dc/parksmap-green --readiness --failure-threshold 5 --initial-delay-seconds 60 --get-url=http://:8080/ws/healthz/ -n ${GUID}-parks-prod
oc set probe dc/mlbparks-green --liveness --failure-threshold 5 --initial-delay-seconds 30 -- echo ok -n ${GUID}-parks-prod
oc set probe dc/mlbparks-green --readiness --failure-threshold 3 --initial-delay-seconds 60 --get-url=http://:8080/ws/healthz/ -n ${GUID}-parks-prod
oc set probe dc/nationalparks-green --liveness --failure-threshold 5 --initial-delay-seconds 30 -- echo ok -n ${GUID}-parks-prod
oc set probe dc/nationalparks-green --readiness --failure-threshold 3 --initial-delay-seconds 60 --get-url=http://:8080/ws/healthz/ -n ${GUID}-parks-prod

echo '*********************************************************************************'
echo 'Prod config terminated'
echo '*********************************************************************************'
