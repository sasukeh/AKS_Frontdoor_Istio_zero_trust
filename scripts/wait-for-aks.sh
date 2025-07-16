#!/bin/bash

# wait-for-aks.sh - Wait for AKS cluster creation to complete

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

RESOURCE_GROUP="rg-frontdoor-istio-demo"
CLUSTER_NAME="aks-frontdoor-istio"

echo -e "${BLUE}[INFO]${NC} Waiting for AKS cluster creation to complete..."
echo -e "${BLUE}[INFO]${NC} Resource Group: $RESOURCE_GROUP"
echo -e "${BLUE}[INFO]${NC} Cluster Name: $CLUSTER_NAME"
echo ""

while true; do
    # Check cluster provisioning state
    PROVISION_STATE=$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
    
    if [ "$PROVISION_STATE" = "NotFound" ]; then
        echo -e "${YELLOW}[WARNING]${NC} AKS cluster not found. Please check if the cluster name and resource group are correct."
        exit 1
    elif [ "$PROVISION_STATE" = "Succeeded" ]; then
        echo -e "${GREEN}[SUCCESS]${NC} AKS cluster creation completed successfully!"
        
        # Display cluster information
        echo ""
        echo "=== Cluster Information ==="
        az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --query "{
            name: name,
            location: location,
            kubernetesVersion: kubernetesVersion,
            nodeResourceGroup: nodeResourceGroup,
            fqdn: fqdn,
            powerState: powerState.code,
            provisioningState: provisioningState
        }" -o table
        
        echo ""
        echo "=== Node Pools ==="
        az aks nodepool list --cluster-name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --query "[].{
            Name: name,
            Mode: mode,
            NodeCount: count,
            VmSize: vmSize,
            ProvisioningState: provisioningState
        }" -o table
        
        break
    elif [ "$PROVISION_STATE" = "Failed" ]; then
        echo -e "${YELLOW}[ERROR]${NC} AKS cluster creation failed!"
        echo "Please check the Azure portal for detailed error information."
        exit 1
    else
        echo -e "${BLUE}[INFO]${NC} Current state: $PROVISION_STATE - Still waiting... ($(date '+%H:%M:%S'))"
        sleep 30
    fi
done

echo ""
echo -e "${GREEN}[SUCCESS]${NC} You can now continue with the deployment!"
echo "To get credentials: az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME"
