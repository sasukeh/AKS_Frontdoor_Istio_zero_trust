#!/bin/bash

# deploy.sh - Main deployment script for Front Door + Istio + AKS

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force-cleanup    Force cleanup of existing resources without prompting"
    echo "  --help, -h         Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  FORCE_CLEANUP      Set to 'true' to force cleanup (same as --force-cleanup)"
    echo ""
    echo "Examples:"
    echo "  $0                     # Normal deployment with prompts"
    echo "  $0 --force-cleanup     # Force cleanup existing resources"
    echo "  FORCE_CLEANUP=true $0  # Force cleanup using environment variable"
    echo ""
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force-cleanup)
                export FORCE_CLEANUP=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check if required tools are installed
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command -v az &> /dev/null; then
        missing_tools+=("Azure CLI")
    fi
    
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("Terraform")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install the missing tools and try again."
        exit 1
    fi
    
    log_success "All prerequisites are installed"
}

# Load environment variables
load_env() {
    log_info "Loading environment variables..."
    
    if [ -f "$PROJECT_ROOT/.env" ]; then
        # Export all variables from .env file
        set -a
        source "$PROJECT_ROOT/.env"
        set +a
        log_success "Environment variables loaded from .env file"
    else
        log_warning ".env file not found. Using default values."
        log_warning "Please create .env file from .env.example for production deployment."
    fi
}

# Azure login check
check_azure_login() {
    log_info "Checking Azure CLI login status..."
    
    if ! az account show &> /dev/null; then
        log_warning "Not logged in to Azure CLI"
        log_info "Please run: az login"
        exit 1
    fi
    
    local current_subscription=$(az account show --query name -o tsv)
    log_success "Logged in to Azure. Current subscription: $current_subscription"
    
    # Set subscription if specified
    if [ -n "${AZURE_SUBSCRIPTION_ID:-}" ]; then
        log_info "Setting subscription to: $AZURE_SUBSCRIPTION_ID"
        az account set --subscription "$AZURE_SUBSCRIPTION_ID"
    fi
}

# Clean up existing resources
cleanup_existing_resources() {
    log_info "Checking for existing resources..."
    
    # Check if resource group exists
    if az group show --name "rg-frontdoor-istio-demo" &> /dev/null; then
        log_warning "Found existing resource group: rg-frontdoor-istio-demo"
        
        # Ask user if they want to clean up
        if [ "${FORCE_CLEANUP:-false}" = "true" ]; then
            log_info "FORCE_CLEANUP is set to true. Proceeding with cleanup..."
            cleanup_confirmed="y"
        else
            echo -n "Do you want to delete the existing resource group and all its resources? (y/N): "
            read -r cleanup_confirmed
        fi
        
        if [[ "$cleanup_confirmed" =~ ^[Yy]$ ]]; then
            log_info "Deleting existing resource group and all resources..."
            az group delete --name "rg-frontdoor-istio-demo" --yes --no-wait
            
            log_info "Waiting for resource group deletion to complete..."
            while az group show --name "rg-frontdoor-istio-demo" &> /dev/null; do
                log_info "Still deleting resources... waiting 30 seconds"
                sleep 30
            done
            
            log_success "Existing resources have been cleaned up"
        else
            log_info "Skipping cleanup. Will attempt to import existing resources."
        fi
    else
        log_info "No existing resource group found. Proceeding with deployment."
    fi
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd "$PROJECT_ROOT/terraform"
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    log_info "Downloading provider plugins and initializing modules..."
    terraform init -upgrade
    
    # Plan deployment
    log_info "Planning Terraform deployment..."
    log_info "This may take several minutes as Terraform queries Azure APIs..."
    log_info "To monitor detailed progress in another terminal, run:"
    log_info "  tail -f $PROJECT_ROOT/terraform/terraform.log"
    
    # Set detailed logging for Terraform
    export TF_LOG=INFO
    export TF_LOG_PATH="$PROJECT_ROOT/terraform/terraform.log"
    
    # Run plan with detailed output
    log_info "Analyzing current infrastructure state..."
    
    # Temporarily disable exit on error for terraform plan
    set +e
    terraform plan \
        -out=tfplan \
        -detailed-exitcode \
        -input=false \
        -parallelism=10 \
        -no-color
    
    local plan_exit_code=$?
    # Re-enable exit on error
    set -e
    
    log_info "Terraform plan exit code: $plan_exit_code"
    
    case $plan_exit_code in
        0)
            log_info "No changes needed - infrastructure is up to date"
            log_info "Skipping terraform apply as no changes are required"
            ;;
        1)
            log_error "Terraform plan failed"
            exit 1
            ;;
        2)
            log_info "Changes detected - proceeding with deployment"
            # Apply deployment
            log_info "Applying Terraform deployment..."
            log_info "This will create Azure resources and may take 10-15 minutes..."
            
            # Temporarily disable exit on error for terraform apply
            set +e
            terraform apply \
                -auto-approve \
                -parallelism=10 \
                -no-color \
                tfplan
            
            local apply_exit_code=$?
            # Re-enable exit on error
            set -e
            
            if [ $apply_exit_code -eq 0 ]; then
                log_success "Terraform apply completed successfully"
            elif [ $apply_exit_code -eq 1 ]; then
                # Check if the error is due to existing resources
                log_warning "Terraform apply failed. Checking if this is due to existing resources..."
                
                # Try to import existing resource group if it exists
                if az group show --name "rg-frontdoor-istio-demo" &> /dev/null; then
                    log_info "Found existing resource group. Attempting to import into Terraform state..."
                    terraform import azurerm_resource_group.main "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/rg-frontdoor-istio-demo" || true
                    
                    # Retry terraform apply after import
                    log_info "Retrying Terraform apply after import..."
                    set +e
                    terraform apply \
                        -auto-approve \
                        -parallelism=10 \
                        -no-color \
                        tfplan
                    apply_exit_code=$?
                    set -e
                    
                    if [ $apply_exit_code -eq 0 ]; then
                        log_success "Terraform apply completed successfully after import"
                    else
                        log_error "Terraform apply still failed after import attempt. You may need to clean up existing resources manually."
                        log_error "Consider running: az group delete --name rg-frontdoor-istio-demo --yes"
                        exit 1
                    fi
                else
                    log_error "Terraform apply failed with exit code: $apply_exit_code"
                    exit 1
                fi
            else
                log_error "Terraform apply failed with exit code: $apply_exit_code"
                exit 1
            fi
            ;;
        *)
            log_error "Unexpected exit code from terraform plan: $plan_exit_code"
            exit 1
            ;;
    esac
    
    # Disable detailed logging after deployment
    unset TF_LOG
    unset TF_LOG_PATH
    
    # Get outputs only if plan was applied
    if [ $plan_exit_code -eq 2 ] || [ $plan_exit_code -eq 0 ]; then
        log_info "Getting Terraform outputs..."
        RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
        AKS_CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
        FRONTDOOR_URL=$(terraform output -raw connection_info | jq -r '.frontdoor_url')
        
        log_success "Infrastructure deployment completed"
        log_info "Resource Group: $RESOURCE_GROUP_NAME"
        log_info "AKS Cluster: $AKS_CLUSTER_NAME"
        log_info "Front Door URL: $FRONTDOOR_URL"
    fi
    
    cd "$PROJECT_ROOT"
}

# Configure kubectl
configure_kubectl() {
    log_info "Configuring kubectl for AKS cluster..."
    
    az aks get-credentials \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --name "$AKS_CLUSTER_NAME" \
        --overwrite-existing
    
    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    
    log_success "kubectl configured successfully"
}

# Wait for Istio to be ready
wait_for_istio() {
    log_info "Waiting for Istio to be ready..."
    
    # Wait for Istio namespace
    kubectl wait --for=condition=Ready pods -n istio-system --all --timeout=300s
    
    # Check if Istio ingress gateway is ready
    kubectl wait --for=condition=Ready pods -n istio-system -l app=istio-ingressgateway --timeout=300s
    
    log_success "Istio is ready"
}

# Deploy applications
deploy_applications() {
    log_info "Deploying sample applications..."
    
    # Apply application manifests
    kubectl apply -f "$PROJECT_ROOT/kubernetes/applications/"
    
    # Wait for applications to be ready
    log_info "Waiting for applications to be ready..."
    kubectl wait --for=condition=Ready pods -l app=frontend --timeout=300s
    kubectl wait --for=condition=Ready pods -l app=backend --timeout=300s
    
    log_success "Applications deployed successfully"
}

# Configure Istio
configure_istio() {
    log_info "Configuring Istio networking and security..."
    
    # Apply Istio configurations
    kubectl apply -f "$PROJECT_ROOT/kubernetes/istio/"
    
    # Wait for gateway to be ready
    sleep 30
    
    log_success "Istio configuration applied"
}

# Get service information
get_service_info() {
    log_info "Getting service information..."
    
    # Get Istio ingress gateway external IP
    local istio_ip
    istio_ip=$(kubectl get service istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending")
    
    echo ""
    echo "=== Deployment Summary ==="
    echo "Resource Group: $RESOURCE_GROUP_NAME"
    echo "AKS Cluster: $AKS_CLUSTER_NAME"
    echo "Front Door URL: $FRONTDOOR_URL"
    echo "Istio Ingress Gateway IP: $istio_ip"
    echo ""
    echo "=== Access Information ==="
    echo "Frontend URL (via Front Door): $FRONTDOOR_URL"
    echo "Frontend URL (direct to Istio): http://$istio_ip"
    echo ""
    echo "=== Useful Commands ==="
    echo "kubectl get pods --all-namespaces"
    echo "kubectl get svc -n istio-system"
    echo "kubectl logs -n istio-system -l app=istio-ingressgateway"
    echo ""
}

# Main deployment function
main() {
    log_info "Starting deployment of Front Door + Istio + AKS..."
    
    parse_args "$@"
    check_prerequisites
    load_env
    check_azure_login
    cleanup_existing_resources
    deploy_infrastructure
    
    # Check if required variables are set
    if [ -z "${RESOURCE_GROUP_NAME:-}" ] || [ -z "${AKS_CLUSTER_NAME:-}" ]; then
        log_error "Required variables not set. RESOURCE_GROUP_NAME: ${RESOURCE_GROUP_NAME:-}, AKS_CLUSTER_NAME: ${AKS_CLUSTER_NAME:-}"
        log_error "This might indicate that terraform outputs were not retrieved properly."
        exit 1
    fi
    
    configure_kubectl
    wait_for_istio
    deploy_applications
    configure_istio
    get_service_info
    
    log_success "Deployment completed successfully!"
    log_info "You can now test the connectivity using: ./scripts/test-connectivity.sh"
}

# Error handling
trap 'log_error "Deployment failed at line $LINENO"' ERR

# Parse command line arguments first
parse_args "$@"

# Run main function
main
