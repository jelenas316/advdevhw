#!/bin/bash
# Setup Jenkins Project
if [ "$#" -ne 3 ]; then
    echo "Usage:"
    echo "  $0 GUID REPO CLUSTER"
    echo "  Example: $0 wkha https://github.com/wkulhanek/ParksMap na39.openshift.opentlc.com"
    exit 1
fi



GUID=$1
REPO=$2
CLUSTER=$3
echo "Setting up Jenkins in project ${GUID}-jenkins from Git Repo ${REPO} for Cluster ${CLUSTER}"

# Code to set up the Jenkins project to execute the
# three pipelines.
# This will need to also build the custom Maven Slave Pod
# Image to be used in the pipelines.
# Finally the script needs to create three OpenShift Build
# Configurations in the Jenkins Project to build the
# three micro services. Expected name of the build configs:
# * mlbparks-pipeline
# * nationalparks-pipeline
# * parksmap-pipeline
# The build configurations need to have two environment variables to be passed to the Pipeline:
# * GUID: the GUID used in all the projects
# * CLUSTER: the base url of the cluster used (e.g. na39.openshift.opentlc.com)


##### Update nexus_settings file with right GUID and CLUSTER

#sed -i "s/GUID/${GUID}/"     nexus_settings.xml
#sed -i "s/CLUSTER{$CLUSTER}/"   nexus_settings.xml


#####Create a Jenkins instance with persistent storage and sufficient resources


#mkdir jenkins-slave-appdev

#oc new-project $GUID-jenkins  --display-name "Shared Jenkins"

#oc policy add-role-to-user admin ${USER} -n ${GUID}-jenkins

#oc annotate namespace ${GUID}-jenkins openshift.io/requester=${USER} --overwrite
oc project $GUID-jenkins
#oc new-app -f ./Infrastructure/templates/jenkins.json --param ENABLE_OAUTH=true --param MEMORY_LIMIT=2Gi --param VOLUME_CAPACITY=4Gi --param CPU_LIMIT=2
#echo "Setting up Jenkins in project ${GUID}-jenkins from Git Repo ${REPO} for Cluster ${CLUSTER}"
#oc -n $GUID-jenkins new-app -f Infrastructure/templates/jenkins.yml -p MEMORY_LIMIT=2Gi -p VOLUME_CAPACITY=4Gi
#oc -n $GUID-jenkins rollout status dc/jenkins -w

echo "Setting up Jenkins in project ${GUID}-jenkins from Git Repo ${REPO} for Cluster ${CLUSTER}"
oc new-app jenkins-persistent --param ENABLE_OAUTH=true --param MEMORY_LIMIT=4Gi --param VOLUME_CAPACITY=4Gi -n ${GUID}-jenkins
oc rollout pause dc jenkins -n ${GUID}-jenkins
oc set resources dc jenkins --limits=memory=4Gi,cpu=2 --requests=memory=2Gi,cpu=1 -n ${GUID}-jenkins
oc rollout resume dc jenkins -n ${GUID}-jenkins


while : ; do
    oc get pod -n ${GUID}-jenkins | grep -v deploy | grep "1/1"
    echo "Checking if Jenkins is Ready..."
    if [ $? == "1" ] 
      then 
      echo "Wait 10 seconds..."
        sleep 10
      else 
        break 
    fi
done



oc new-build --name=jenkins-slave-appdev --dockerfile=$'FROM docker.io/openshift/jenkins-slave-maven-centos7:v3.9\nUSER root\nRUN yum -y install skopeo apb && \yum clean all\nUSER 1001' -n ${GUID}-jenkins

while : ; do

echo "Checking if Jenkins-app-slave is completed..."
     
oc get pod -n ${GUID}-jenkins | grep 'slave' | grep "Completed"
     
    if [ $? == "0" ] 
      then 
        echo 'jenkins-slave-appdev build completed'
        break
      else 
        echo '...sleep 10 seconds....'
        sleep 10
    fi
done


oc create configmap basic-config --from-literal="GUID=${GUID}" --from-literal="REPO=${REPO}" --from-literal="CLUSTER=${CLUSTER}"

#oc new-build --name=jenkins-slave-appdev   --dockerfile="$(< ./Infrastructure/templates/docker/skopeo/Dockerfile)"  -n $GUID-jenkins

oc create -f Infrastructure/templates/bl-mlbparks.yml -n ${GUID}-jenkins
oc create -f Infrastructure/templates/bl-nationalparks.yml -n ${GUID}-jenkins
oc create -f Infrastructure/templates/bl-parksmap.yml -n ${GUID}-jenkins

oc set env bc/mlbparks-pipeline GUID=${GUID} REPO=${REPO} CLUSTER=${CLUSTER} -n ${GUID}-jenkins
oc set env bc/nationalparks-pipeline GUID=${GUID} REPO=${REPO} CLUSTER=${CLUSTER} -n ${GUID}-jenkins
oc set env bc/parksmap-pipeline GUID=${GUID} REPO=${REPO} CLUSTER=${CLUSTER} -n ${GUID}-jenkins


# Deploy on DEV
#cd  jenkins-slave-appdev
#echo "FROM docker.io/openshift/jenkins-slave-maven-centos7:v3.9
#USER root
#RUN yum -y install skopeo apb && \
#    yum clean all
#USER 1001"  >  jenkins-slave-appdev/Dockerfile
######  Set up three build configurations with pointers to the pipelines in the source code project. Each build configuration needs to point to the source code repository and the respective contextDir
#cd jenkins-slave-appdev
#docker build . -t docker-registry-default.apps.$CLUSTER/$GUID-jenkins/jenkins-slave-maven-appdev:v3.9
#docker build . -t docker-registry-default.apps.$CLUSTER/$GUID-jenkins/jenkins-slave-maven-appuat:v3.9
#docker build . -t docker-registry-default.apps.$CLUSTER/$GUID-jenkins/jenkins-slave-maven-appprod:v3.9
#sudo docker login -u $GUID -p $(oc whoami -t) docker-registry-default.apps.$CLUSTER
#sudo docker push docker-registry-default.apps.$CLUSTER/$GUID-jenkins/jenkins-slave-maven-appdev:v3.9
#####     Create a build configuration to build the custom Maven slave pod to include Skopeo
#skopeo copy --dest-tls-verify=false --dest-creds=$(oc whoami):$(oc whoami -t) docker-daemon:docker-registry-default.apps.$CLUSTER/$GUID-jenkins/jenkins-slave-maven-appdev:v3.9 docker://docker-registry-default.apps.$CLUSTER/$GUID-jenkins/jenkins-slave-maven-appdev:v3.9


