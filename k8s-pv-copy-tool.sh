#!/usr/bin/env bash

#################################
###                           ###  
###     K8S-PV-COPY-TOOL      ###
###                           ###
#################################

# Handy script to easily migrate PV data from one cluster to another

# ATTENTION:
# This script can cause data loss or corruption. Proceed with caution!

# REQUIREMENTS:
# - PVC and PV must alredy be created on source and destination for this script to function properly.
# - PVs must not be mounted.

# Required args:
# -n | --namespace = namespace of PV and created Pod
# -s | --source-context = source cluster's context
# -d | --dest-context = destination cluster's context
# -v | --pvc-name = which pvc needs to be attached to Pod
# -p | --path = which path needs to be copied

name="k8s-pv-copy-tool"

while [[ "$1" =~ ^- && ! "$1" == "--" ]]; do case $1 in
  -h | --help )
    shift; echo "Usage: ${0} [args]

Arguments:
--help            (-h)    get help
--namespace       (-n)    namespace of PVC and Pod
--source-context  (-s)    source kubeContext
--dest-context    (-d)    destination kubeContext
--pvc-name        (-v)    PVC name, same for source and destination
--path            (-p)    path to copy, same for source and destination";
    exit
    ;;
  -n | --namespace )
    shift; namespace=$1
    ;;
  -s | --source-context )
    shift; source_context=$1
    ;;
  -d | --dest-context )
    shift; dest_context=$1
    ;;
  -v | --pvc-name )
    shift; pvc_name=$1
    ;;
  -p | --path )
    shift; path=$1
    ;;
  -r | --remove )
    shift; remove_pods=1
    ;;
esac; shift; done

if [[ -z $remove_pods ]]
then
  echo "apiVersion: v1
  kind: Pod
  metadata:
    name: ${name}
    namespace: ${namespace}
    labels:
      name: ${name}
  spec:
    containers:
    - name: ${name}-busybox
      image: busybox
      command: 
        - sh
        - -c
        - --
      args: 
        - 'while true; do sleep 30; done'
      volumeMounts:
        - mountPath: ${path}
          name: ${name}-volume
    volumes:
    - name: ${name}-volume
      persistentVolumeClaim:
        claimName: ${pvc_name}" | tee >(kubectl --context $source_context apply -f -) >(kubectl --context $dest_context apply -f -) > /dev/null

  echo "Waiting 60 seconds for pods to start..."
  sleep 60

  echo "Copying ${namespace}/${pvc_name}:${path} from ${source_context} to ${dest_context}..."
  kubectl exec --context $source_context --namespace $namespace $name -- tar cf - $path | \
  kubectl exec --context $dest_context --namespace $namespace -i $name -- tar xvf - -C /
fi

if [[ ! -z $remove_pods ]]
then
  echo "Removing pod ${namespace}/${name} from ${source_context}..."
  kubectl --context $source_context --namespace $namespace delete pod $name --force >/dev/null 2>&1
  echo "Removing pod ${namespace}/${name} from ${dest_context}..."
  kubectl --context $dest_context --namespace $namespace delete pod $name --force >/dev/null 2>&1
  echo "Done!"
fi
