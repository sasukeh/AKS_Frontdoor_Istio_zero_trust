#!/bin/bash

# Exit on any error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Check if running from the correct directory
if [ ! -f "terraform/main.tf" ]; then
    print_error "Please run this script from the project root directory"
    exit 1
fi

print_header "🚀 Azure Front Door + Istio + AKS Deployment (Public Cluster)"

# Step 1: Deploy Infrastructure
print_info "Step 1: Deploying Azure infrastructure with Terraform..."
cd terraform

terraform init
terraform plan -out=tfplan
terraform apply tfplan

print_success "Infrastructure deployment completed!"

# Get AKS credentials (simplified for public cluster)
print_info "Getting AKS credentials..."
AKS_NAME=$(terraform output -raw aks_cluster_name)
RESOURCE_GROUP=$(terraform output -raw resource_group_name)

az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_NAME" --overwrite-existing

cd ..

# Step 2: Wait for AKS and verify access
print_info "Step 2: Verifying AKS cluster access..."
kubectl get nodes

print_info "Waiting for AKS cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Step 3: Verify Istio installation
print_info "Step 3: Verifying Istio installation..."
kubectl get pods -n istio-system

print_info "Waiting for Istio components to be ready..."
kubectl wait --for=condition=Ready pods --all -n istio-system --timeout=300s

# Step 4: Deploy demo application
print_info "Step 4: Deploying demo application..."
kubectl apply -f kubernetes/demo-app.yaml

# Step 5: Configure Istio Gateway
print_info "Step 5: Configuring Istio Gateway..."
kubectl apply -f kubernetes/istio-gateway.yaml

# Step 6: Setup Private Link Service
print_info "Step 6: Setting up Private Link Service..."
kubectl apply -f kubernetes/private-link-service.yaml

# Step 7: Wait for services to be ready
print_info "Step 7: Waiting for services to be ready..."
kubectl wait --for=condition=Ready pods -n frontdoor-demo --timeout=300s

# Step 8: Get service information
print_info "Step 8: Getting service information..."
print_info "Waiting for LoadBalancer IP..."
sleep 60

EXTERNAL_IP=""
ATTEMPTS=0
MAX_ATTEMPTS=20

while [ -z "$EXTERNAL_IP" ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    print_info "Attempt $((ATTEMPTS+1))/$MAX_ATTEMPTS: Waiting for External IP..."
    EXTERNAL_IP=$(kubectl get svc istio-gateway-pls -n istio-system --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}" 2>/dev/null || echo "")
    if [ -z "$EXTERNAL_IP" ]; then
        sleep 30
        ATTEMPTS=$((ATTEMPTS+1))
    fi
done

if [ -n "$EXTERNAL_IP" ]; then
    print_success "External IP obtained: $EXTERNAL_IP"
else
    print_warning "Could not obtain External IP automatically. Please check manually:"
    echo "kubectl get svc istio-gateway-pls -n istio-system"
fi

# Step 9: Display connection information
print_header "🎉 Deployment Complete!"

echo -e "${GREEN}📊 Infrastructure Information:${NC}"
cd terraform
echo "🏗️  Resource Group: $(terraform output -raw resource_group_name)"
echo "🔗 AKS Cluster: $(terraform output -raw aks_cluster_name)"
echo "🌐 Front Door URL: $(terraform output -raw frontdoor_url)"
if [ -n "$EXTERNAL_IP" ]; then
    echo "🔒 Private Link Service IP: $EXTERNAL_IP"
fi
cd ..

echo -e "\n${GREEN}🔧 Verification Commands:${NC}"
echo "kubectl get pods -n istio-system"
echo "kubectl get pods -n frontdoor-demo"
echo "kubectl get svc -n istio-system"
echo "kubectl get gateway,virtualservice -n frontdoor-demo"

echo -e "\n${GREEN}🌐 Test URLs:${NC}"
if [ -n "$EXTERNAL_IP" ]; then
    echo "Internal Test: http://$EXTERNAL_IP"
fi
echo "Front Door: $(cd terraform && terraform output -raw frontdoor_url)"

echo -e "\n${YELLOW}📝 Next Steps:${NC}"
echo "1. Wait for Private Link Service to be fully provisioned"
echo "2. Configure Front Door origin to point to Private Link Service"
echo "3. Test the connection: Front Door → PLS → Istio → Pod"
echo "4. Monitor traffic flow through Istio"

print_success "Deployment completed successfully! 🎉"
