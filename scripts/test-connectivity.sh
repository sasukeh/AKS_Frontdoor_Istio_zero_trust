#!/bin/bash

# test-connectivity.sh - Test connectivity to deployed services

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

# Get Front Door URL from Terraform output
get_frontdoor_url() {
    cd "$PROJECT_ROOT/terraform"
    FRONTDOOR_URL=$(terraform output -raw connection_info | jq -r '.frontdoor_url' 2>/dev/null || echo "")
    cd "$PROJECT_ROOT"
    
    if [ -z "$FRONTDOOR_URL" ]; then
        log_error "Could not get Front Door URL from Terraform output"
        exit 1
    fi
    
    log_info "Front Door URL: $FRONTDOOR_URL"
}

# Get Istio Gateway IP
get_istio_gateway_ip() {
    ISTIO_IP=$(kubectl get service istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [ -z "$ISTIO_IP" ]; then
        log_warning "Istio Ingress Gateway IP not available yet"
        return 1
    fi
    
    log_info "Istio Ingress Gateway IP: $ISTIO_IP"
    return 0
}

# Test Front Door connectivity
test_frontdoor() {
    log_info "Testing Front Door connectivity..."
    
    local response
    local status_code
    
    # Test HTTPS endpoint
    log_info "Testing HTTPS endpoint: $FRONTDOOR_URL"
    
    if response=$(curl -s -o /dev/null -w "%{http_code}" -L "$FRONTDOOR_URL" --max-time 30); then
        if [ "$response" = "200" ]; then
            log_success "Front Door HTTPS endpoint is responding (HTTP $response)"
        else
            log_warning "Front Door HTTPS endpoint returned HTTP $response"
        fi
    else
        log_error "Failed to connect to Front Door HTTPS endpoint"
        return 1
    fi
    
    # Test API endpoint
    log_info "Testing API endpoint: $FRONTDOOR_URL/api"
    
    if response=$(curl -s "$FRONTDOOR_URL/api" --max-time 30); then
        if echo "$response" | jq . > /dev/null 2>&1; then
            log_success "API endpoint is responding with valid JSON"
            echo "API Response: $response"
        else
            log_warning "API endpoint is responding but not with valid JSON"
            echo "Response: $response"
        fi
    else
        log_error "Failed to connect to API endpoint"
        return 1
    fi
}

# Test Istio Gateway direct connectivity
test_istio_direct() {
    log_info "Testing direct Istio Gateway connectivity..."
    
    if ! get_istio_gateway_ip; then
        log_warning "Skipping direct Istio test - Gateway IP not available"
        return 0
    fi
    
    local response
    
    # Test HTTP endpoint (should redirect to HTTPS)
    log_info "Testing HTTP endpoint: http://$ISTIO_IP"
    
    if response=$(curl -s -o /dev/null -w "%{http_code}" "http://$ISTIO_IP" --max-time 30); then
        if [ "$response" = "301" ] || [ "$response" = "302" ]; then
            log_success "HTTP endpoint correctly redirects to HTTPS (HTTP $response)"
        elif [ "$response" = "200" ]; then
            log_success "HTTP endpoint is responding (HTTP $response)"
        else
            log_warning "HTTP endpoint returned HTTP $response"
        fi
    else
        log_error "Failed to connect to HTTP endpoint"
        return 1
    fi
    
    # Test API endpoint
    log_info "Testing API endpoint: http://$ISTIO_IP/api"
    
    if response=$(curl -s "http://$ISTIO_IP/api" --max-time 30); then
        if echo "$response" | jq . > /dev/null 2>&1; then
            log_success "Direct API endpoint is responding with valid JSON"
            echo "API Response: $response"
        else
            log_warning "Direct API endpoint is responding but not with valid JSON"
            echo "Response: $response"
        fi
    else
        log_error "Failed to connect to direct API endpoint"
        return 1
    fi
}

# Test service mesh connectivity
test_service_mesh() {
    log_info "Testing service mesh connectivity..."
    
    # Check if pods are running with Istio sidecars
    local frontend_pods
    local backend_pods
    
    frontend_pods=$(kubectl get pods -l app=frontend -o jsonpath='{.items[*].spec.containers[*].name}' | grep -o istio-proxy | wc -l || echo "0")
    backend_pods=$(kubectl get pods -l app=backend -o jsonpath='{.items[*].spec.containers[*].name}' | grep -o istio-proxy | wc -l || echo "0")
    
    if [ "$frontend_pods" -gt 0 ]; then
        log_success "Frontend pods have Istio sidecars ($frontend_pods pods)"
    else
        log_error "Frontend pods missing Istio sidecars"
        return 1
    fi
    
    if [ "$backend_pods" -gt 0 ]; then
        log_success "Backend pods have Istio sidecars ($backend_pods pods)"
    else
        log_error "Backend pods missing Istio sidecars"
        return 1
    fi
    
    # Test mTLS
    log_info "Checking mTLS configuration..."
    
    if kubectl get peerauthentication default -n istio-system &> /dev/null; then
        log_success "mTLS PeerAuthentication policy is configured"
    else
        log_warning "mTLS PeerAuthentication policy not found"
    fi
}

# Test load balancing
test_load_balancing() {
    log_info "Testing load balancing..."
    
    local unique_hostnames=()
    
    for i in {1..5}; do
        response=$(curl -s "$FRONTDOOR_URL/api" --max-time 10 2>/dev/null || echo '{"hostname":"error"}')
        hostname=$(echo "$response" | jq -r '.hostname' 2>/dev/null || echo "unknown")
        
        if [[ " ${unique_hostnames[@]} " =~ " ${hostname} " ]]; then
            continue
        else
            unique_hostnames+=("$hostname")
        fi
        
        sleep 1
    done
    
    if [ ${#unique_hostnames[@]} -gt 1 ]; then
        log_success "Load balancing is working - got ${#unique_hostnames[@]} different backend instances"
        printf '%s\n' "${unique_hostnames[@]}" | sed 's/^/  - /'
    else
        log_warning "Only one backend instance responded (${unique_hostnames[0]})"
    fi
}

# Performance test
performance_test() {
    log_info "Running basic performance test..."
    
    log_info "Testing 10 concurrent requests..."
    
    local start_time
    local end_time
    local duration
    
    start_time=$(date +%s.%N)
    
    for i in {1..10}; do
        curl -s "$FRONTDOOR_URL" -o /dev/null --max-time 30 &
    done
    
    wait
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)
    
    log_success "10 concurrent requests completed in ${duration}s"
}

# Display system status
show_status() {
    log_info "System Status Summary"
    echo ""
    echo "=== Kubernetes Cluster ==="
    kubectl get nodes
    echo ""
    echo "=== Istio System Pods ==="
    kubectl get pods -n istio-system
    echo ""
    echo "=== Application Pods ==="
    kubectl get pods -l app=frontend
    kubectl get pods -l app=backend
    echo ""
    echo "=== Services ==="
    kubectl get svc
    kubectl get svc -n istio-system
    echo ""
    echo "=== Istio Configuration ==="
    kubectl get gateway
    kubectl get virtualservice
    kubectl get destinationrule
    echo ""
}

# Main test function
main() {
    log_info "Starting connectivity tests..."
    
    # Check prerequisites
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        log_error "curl not found. Please install curl."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Please install jq."
        exit 1
    fi
    
    # Get URLs
    get_frontdoor_url
    
    # Run tests
    echo ""
    test_service_mesh
    echo ""
    test_frontdoor
    echo ""
    test_istio_direct
    echo ""
    test_load_balancing
    echo ""
    performance_test
    echo ""
    show_status
    
    log_success "All connectivity tests completed!"
}

# Error handling
trap 'log_error "Test failed at line $LINENO"' ERR

# Run main function
main "$@"
