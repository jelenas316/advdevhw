#!/bin/bash
	# Setup Development Project
	if [ "$#" -ne 1 ]; then
	    echo "Usage:"
	    echo "  $0 GUID"
	    exit 1
	fi

	GUID=$1
	echo "Setting up Parks Development Environment in project ${GUID}-parks-dev"
	

	######   Create ConfigMaps for configuration of the applications
	oc project $GUID-parks-dev 
	oc policy add-role-to-user view --serviceaccount=default -n $GUID-parks-dev
	oc policy add-role-to-user edit system:serviceaccount:$GUID-jenkins:jenkins -n $GUID-parks-dev
	oc policy add-role-to-user admin system:serviceaccount:gpte-jenkins:jenkins -n $GUID-parks-dev
	oc policy add-role-to-user view --serviceaccount=default
	
	oc create configmap mongodb-configmap        --from-literal=DB_HOST=mongodb    --from-literal=DB_PORT=27017   --from-literal=DB_USERNAME=mongodb     --from-literal=DB_PASSWORD=mongodb   --from-literal=DB_NAME=parks   --from-literal=DB_REPLICASET=rs0	
	oc create configmap mlbparks-config --from-literal="APPNAME=MLB Parks (Dev)" --from-literal="DB_HOST=mongodb" --from-literal="DB_PORT=27017" --from-literal="DB_USERNAME=mongodb" --from-literal="DB_PASSWORD=mongodb" --from-literal="DB_NAME=parks" -n ${GUID}-parks-dev
	oc create configmap nationalparks-config --from-literal="APPNAME=National Parks (Dev)" --from-literal="DB_HOST=mongodb" --from-literal="DB_PORT=27017" --from-literal="DB_USERNAME=mongodb" --from-literal="DB_PASSWORD=mongodb" --from-literal="DB_NAME=parks" -n ${GUID}-parks-dev
	oc create configmap parksmap-config --from-literal="APPNAME=ParksMap (Dev)" -n ${GUID}-parks-dev

	oc new-app -e MONGODB_USER=mongodb -e MONGODB_PASSWORD=mongodb -e MONGODB_DATABASE=parks -e MONGODB_ADMIN_PASSWORD=mongodb --name=mongodb registry.access.redhat.com/rhscl/mongodb-34-rhel7:latest -n ${GUID}-parks-dev
	
	while : ; do
	    oc get pod -n ${GUID}-parks-dev | grep -v deploy | grep "1/1"
	    echo "Checking if MongoDB is Ready..."
	    if [ $? == "1" ] 
	      then 
	      echo "Wait 10 seconds..."
	        sleep 10
	      else 
	        break 
	    fi
	done
	

	# Now build all parks apps
	
	oc new-build --binary=true  --name=mlbparks jboss-eap70-openshift:1.7 -n ${GUID}-parks-dev
	oc new-build --binary=true  --name=nationalparks redhat-openjdk18-openshift:1.2 -n ${GUID}-parks-dev
	oc new-build --binary=true  --name=parksmap redhat-openjdk18-openshift:1.2 -n ${GUID}-parks-dev
	
	#create applications
	

	
	echo 'Create app'
	
	oc new-app ${GUID}-parks-dev/mlbparks:0.0-0 --name=mlbparks --allow-missing-imagestream-tags=true -n ${GUID}-parks-dev
	oc new-app ${GUID}-parks-dev/nationalparks:0.0-0 --name=nationalparks --allow-missing-imagestream-tags=true -n ${GUID}-parks-dev
	oc new-app ${GUID}-parks-dev/parksmap:0.0-0 --name=parksmap --allow-missing-imagestream-tags=true -n ${GUID}-parks-dev

	echo 'Set triggers - remove'
	
	oc set triggers dc/mlbparks --remove-all -n ${GUID}-parks-dev
	oc set triggers dc/nationalparks --remove-all -n ${GUID}-parks-dev
	oc set triggers dc/parksmap --remove-all -n ${GUID}-parks-dev
	

	echo   'Expose and label the services properly (parksmap-backend)'
	
	oc expose dc mlbparks --port 8080 --labels="type=parksmap-backend" -n ${GUID}-parks-dev
	oc expose dc nationalparks --port 8080 --labels="type=parksmap-backend" -n ${GUID}-parks-dev
	oc expose dc parksmap --port 8080 -n ${GUID}-parks-dev
	oc expose svc mlbparks --labels="type=parksmap-backend" -n ${GUID}-parks-dev
	oc expose svc nationalparks --labels="type=parksmap-backend" -n ${GUID}-parks-dev
	oc expose svc parksmap -n ${GUID}-parks-dev

	

	echo 'Set up liveness and readiness probes'
	oc set probe dc/mlbparks --readiness     --initial-delay-seconds 30 --failure-threshold 3   --get-url=http://:8080/ws/healthz/ -n ${GUID}-parks-dev
	oc set probe dc/mlbparks --liveness      --initial-delay-seconds 30 --failure-threshold 3     --get-url=http://:8080/ws/healthz/ -n ${GUID}-parks-dev
	oc set probe dc/nationalparks --readiness     --initial-delay-seconds 30 --failure-threshold 3   --get-url=http://:8080/ws/healthz/ -n ${GUID}-parks-dev
	oc set probe dc/nationalparks --liveness      --initial-delay-seconds 30 --failure-threshold 3     --get-url=http://:8080/ws/healthz/ -n ${GUID}-parks-dev
	oc set probe dc/parksmap --readiness     --initial-delay-seconds 30 --failure-threshold 3   --get-url=http://:8080/ws/healthz/ -n ${GUID}-parks-dev
	oc set probe dc/parksmap --liveness      --initial-delay-seconds 30 --failure-threshold 3     --get-url=http://:8080/ws/healthz/ -n ${GUID}-parks-dev
	
	echo 'Configure the deployment configurations using the ConfigMaps'

	oc set env dc/mlbparks --from=configmap/mlbparks-config -n ${GUID}-parks-dev
	oc set env dc/nationalparks --from=configmap/nationalparks-config -n ${GUID}-parks-dev
	oc set env dc/parksmap --from=configmap/parksmap-config -n ${GUID}-parks-dev
	

	echo 'oc  set deployment hooks'
	    
	oc set deployment-hook dc/mlbparks  -n ${GUID}-parks-dev --post -c mlbparks --failure-policy=retry -- curl http://mlbparks.${GUID}-parks-dev.svc.cluster.local:8080/ws/data/load/
	oc set deployment-hook dc/nationalparks  -n ${GUID}-parks-dev --post -c nationalparks --failure-policy=retry -- curl http://nationalparks.${GUID}-parks-dev.svc.cluster.local:8080/ws/data/load/



        echo '********************************************************'
	echo 'Dev deployment terminated'
	echo '********************************************************'
	
