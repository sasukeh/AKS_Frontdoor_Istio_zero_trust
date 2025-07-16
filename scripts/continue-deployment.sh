#!/bin/bash

# continue-deployment.sh - Continue deployment after AKS timeout

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Change to terraform directory
cd "$PROJECT_ROOT/terraform"

log_info "Checking current AKS cluster status..."
if az aks show --name aks-frontdoor-istio --resource-group rg-frontdoor-istio-demo &> /dev/null; then
    PROVISION_STATE=$(az aks show --name aks-frontdoor-istio --resource-group rg-frontdoor-istio-demo --query "provisioningState" -o tsv)
    log_info "AKS cluster state: $PROVISION_STATE"
    
    if [ "$PROVISION_STATE" = "Succeeded" ]; then
        log_success "AKS cluster is ready! Proceeding with Terraform import and deployment."
        
        # Try to import AKS cluster
        log_info "Importing AKS cluster into Terraform state..."
        terraform import module.aks.azurerm_kubernetes_cluster.main "/subscriptions/8f4244ad-7467-4361-a52e-57052eb23ca2/resourceGroups/rg-frontdoor-istio-demo/providers/Microsoft.ContainerService/managedClusters/aks-frontdoor-istio" || log_warning "AKS import failed, continuing..."
        
        # Deploy remaining resources
        log_info "Deploying remaining resources..."
        terraform apply -auto-approve
        
        # Get outputs
        log_info "Getting deployment outputs..."
        RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
        AKS_CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
        
        # Check if frontdoor_url exists in outputs
        if terraform output connection_info &> /dev/null; then
            local connection_info_json=$(terraform output -json connection_info)
            FRONTDOOR_URL=$(echo "$connection_info_json" | jq -r '.frontdoor_url // empty')
        else
            FRONTDOOR_URL=""
        fi
        
        log_success "Infrastructure is ready!"
        log_info "Resource Group: $RESOURCE_GROUP_NAME"
        log_info "AKS Cluster: $AKS_CLUSTER_NAME"
        if [ -n "$FRONTDOOR_URL" ]; then
            log_info "Front Door URL: $FRONTDOOR_URL"
        else
            log_warning "Front Door URL not available yet"
        fi
        
        # Configure kubectl
        log_info "Configuring kubectl..."
        az aks get-credentials --resource-group "$RESOURCE_GROUP_NAME" --name "$AKS_CLUSTER_NAME" --overwrite-existing
        
        # Check cluster nodes
        log_info "Checking cluster nodes..."
        kubectl get nodes
        
        # Check Istio
        log_info "Checking Istio installation..."
        kubectl get pods -n istio-system || log_warning "Istio pods not found yet"
        
        log_success "Deployment continuation completed!"
        echo ""
        echo "Next steps:"
        echo "1. Wait for all pods to be ready: kubectl get pods --all-namespaces"
        echo "2. Deploy applications: kubectl apply -f $PROJECT_ROOT/kubernetes/applications/"
        echo "3. Configure Istio: kubectl apply -f $PROJECT_ROOT/kubernetes/istio/"
        
    else
        log_warning "AKS cluster is still being created (state: $PROVISION_STATE)"
        log_info "Please wait for the cluster to complete and run this script again."
        exit 1
    fi
else
    log_error "AKS cluster not found!"
    exit 1
fi
