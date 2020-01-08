#!/bin/bash

ENV=$1
CNI=$2
POL=$3

RGNAME=$ENV-aks-rg
DNS_PRE=$ENV-aks

# go to cluster-definitions folder
cd cluster-definitions/

# create a new resource group:
az group create -n "$RGNAME" -l "northeurope"

# then deploy the virtual network using the JSON description above and the following command:
az group deployment create -g  "$RGNAME" --name "$ENV-aks-vnet" --template-file aks-vnet.json

# get the subnet ids
MASTERSUBNET=$(az network vnet subnet show --resource-group "$RGNAME" --vnet-name aks-vnet --name master-subnet --query id --output tsv)
AGENTSUBNET=$(az network vnet subnet show --resource-group "$RGNAME" --vnet-name aks-vnet --name agent-subnet --query id --output tsv)

# set the properties that will be overriden
OPT="MasterProfile.dnsPrefix="$DNS_PRE",orchestratorProfile.kubernetesConfig.networkPlugin="$CNI",masterProfile.vnetSubnetId="$MASTERSUBNET",agentPoolProfiles[0].vnetSubnetId="$AGENTSUBNET

POLSTR="orchestratorProfile.kubernetesConfig.networkPolicy="$POL

# if policy is not given, then use azure policy
[ -n "$POL" ] && OPT="$OPT,$POLSTR"

echo "override str:" $OPT

# create the ARM templates
aks-engine generate --set $OPT aks.json

# go to the output folder
cd _output/$DNS_PRE/

# deploy the cluster
az group deployment create -g "$RGNAME" --name "$ENV-aks" --template-file azuredeploy.json --parameters "@azuredeploy.parameters.json"

# if cni is kubenet then associate the subnet with routing table
if [ "$CNI" = "kubenet" ]
then
    rt=$(az network route-table list -g $RGNAME -o json | jq -r '.[].id')
    az network vnet subnet update -n "agent-subnet" \
    -g $RGNAME \
    --vnet-name "aks-vnet" \
    --route-table $rt
fi

# connect to the cluster
KUBECONFIG=~/.kube/config:kubeconfig/kubeconfig.northeurope.json kubectl config view --flatten >> mergedkube && mv mergedkube ~/.kube/config

# use the newly added context
kubectl config use-context "$ENV-aks"

# show the cluster info
kubectl cluster-info --context "$ENV-aks"