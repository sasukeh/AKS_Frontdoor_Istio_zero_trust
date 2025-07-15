#!/bin/bash

# cleanup.sh - Clean up all deployed resources

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

# Confirmation prompt
confirm_cleanup() {
    echo ""
    log_warning "This will DELETE ALL resources created by this deployment!"
    echo ""
    
    if [ -f "$PROJECT_ROOT/terraform/terraform.tfstate" ]; then
        cd "$PROJECT_ROOT/terraform"
        echo "The following resources will be destroyed:"
        terraform show -json | jq -r '.values.root_module.resources[]?.address' 2>/dev/null | sort || echo "  - Resource list unavailable"
        cd "$PROJECT_ROOT"
        echo ""
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
}

# Clean up Kubernetes resources
cleanup_kubernetes() {
    log_info "Cleaning up Kubernetes resources..."
    
    if kubectl config current-context &> /dev/null; then
        # Delete application resources
        log_info "Deleting application resources..."
        kubectl delete -f "$PROJECT_ROOT/kubernetes/applications/" --ignore-not-found=true || true
        
        # Delete Istio configurations
        log_info "Deleting Istio configurations..."
        kubectl delete -f "$PROJECT_ROOT/kubernetes/istio/" --ignore-not-found=true || true
        
        # Wait for resources to be deleted
        log_info "Waiting for resources to be deleted..."
        sleep 30
        
        log_success "Kubernetes resources cleaned up"
    else
        log_warning "No kubectl context available, skipping Kubernetes cleanup"
    fi
}

# Clean up Terraform resources
cleanup_terraform() {
    log_info "Cleaning up Terraform resources..."
    
    if [ ! -f "$PROJECT_ROOT/terraform/terraform.tfstate" ]; then
        log_warning "No Terraform state file found, skipping Terraform cleanup"
        return 0
    fi
    
    cd "$PROJECT_ROOT/terraform"
    
    # Plan destroy
    log_info "Planning Terraform destroy..."
    terraform plan -destroy -out=tfplan-destroy
    
    # Apply destroy
    log_info "Destroying Terraform resources..."
    terraform apply tfplan-destroy
    
    # Clean up Terraform files
    log_info "Cleaning up Terraform files..."
    rm -f tfplan-destroy
    rm -f tfplan
    rm -f terraform.tfstate.backup
    
    log_success "Terraform resources destroyed"
    
    cd "$PROJECT_ROOT"
}

# Clean up local files
cleanup_local() {
    log_info "Cleaning up local files..."
    
    # Remove kubectl context (optional)
    read -p "Remove kubectl context for this cluster? (y/n): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if kubectl config current-context &> /dev/null; then
            local current_context
            current_context=$(kubectl config current-context)
            kubectl config delete-context "$current_context" || true
            log_info "Kubectl context removed"
        fi
    fi
    
    # Clean up temporary files
    rm -rf "$PROJECT_ROOT/.terraform" 2>/dev/null || true
    rm -f "$PROJECT_ROOT/terraform/.terraform.lock.hcl" 2>/dev/null || true
    
    log_success "Local cleanup completed"
}

# Force cleanup (for emergency situations)
force_cleanup() {
    log_warning "Performing force cleanup..."
    
    # Get resource group name from various sources
    local resource_group=""
    
    # Try to get from Terraform state
    if [ -f "$PROJECT_ROOT/terraform/terraform.tfstate" ]; then
        cd "$PROJECT_ROOT/terraform"
        resource_group=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
        cd "$PROJECT_ROOT"
    fi
    
    # Try to get from environment
    if [ -z "$resource_group" ] && [ -f "$PROJECT_ROOT/.env" ]; then
        resource_group=$(grep "^RESOURCE_GROUP_NAME=" "$PROJECT_ROOT/.env" | cut -d'=' -f2 | tr -d '"' || echo "")
    fi
    
    # Ask user if still not found
    if [ -z "$resource_group" ]; then
        read -p "Enter the resource group name to delete: " resource_group
    fi
    
    if [ -n "$resource_group" ]; then
        log_info "Force deleting resource group: $resource_group"
        az group delete --name "$resource_group" --yes --no-wait || true
        log_warning "Resource group deletion initiated (running in background)"
    else
        log_error "Could not determine resource group name for force cleanup"
    fi
}

# Show cleanup status
show_cleanup_status() {
    log_info "Checking cleanup status..."
    
    # Check for remaining resources
    if [ -f "$PROJECT_ROOT/.env" ]; then
        local resource_group
        resource_group=$(grep "^RESOURCE_GROUP_NAME=" "$PROJECT_ROOT/.env" | cut -d'=' -f2 | tr -d '"' 2>/dev/null || echo "")
        
        if [ -n "$resource_group" ]; then
            if az group show --name "$resource_group" &> /dev/null; then
                log_warning "Resource group '$resource_group' still exists"
                local resource_count
                resource_count=$(az resource list --resource-group "$resource_group" --query "length(@)" -o tsv 2>/dev/null || echo "0")
                log_info "Resources remaining in group: $resource_count"
            else
                log_success "Resource group '$resource_group' has been deleted"
            fi
        fi
    fi
    
    # Check Terraform state
    if [ -f "$PROJECT_ROOT/terraform/terraform.tfstate" ]; then
        local resource_count
        resource_count=$(cd "$PROJECT_ROOT/terraform" && terraform show -json | jq '.values.root_module.resources | length' 2>/dev/null || echo "unknown")
        if [ "$resource_count" = "0" ]; then
            log_success "No resources in Terraform state"
        else
            log_warning "Terraform state contains $resource_count resources"
        fi
    else
        log_success "No Terraform state file found"
    fi
}

# Main cleanup function
main() {
    log_info "Starting cleanup process..."
    
    # Parse command line arguments
    local force_mode=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force_mode=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [--force]"
                echo "  --force  Perform force cleanup without confirmation"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    if [ "$force_mode" = true ]; then
        force_cleanup
    else
        confirm_cleanup
        cleanup_kubernetes
        cleanup_terraform
        cleanup_local
    fi
    
    show_cleanup_status
    
    log_success "Cleanup process completed!"
    log_info "You may want to check the Azure portal to ensure all resources are deleted."
}

# Error handling
trap 'log_error "Cleanup failed at line $LINENO"' ERR

# Run main function
main "$@"
