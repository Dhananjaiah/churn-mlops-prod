#!/bin/bash
# Quick Test Script - Test your setup step by step
# Run: chmod +x scripts/quick_test.sh && ./scripts/quick_test.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_test() {
    echo -e "${YELLOW}Testing: $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
    ((TESTS_PASSED++))
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    ((TESTS_FAILED++))
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Main testing function
main() {
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════╗"
    echo "║   Churn MLOps Quick Test Script      ║"
    echo "╔═══════════════════════════════════════╗"
    echo -e "${NC}"

    # Test 1: Prerequisites
    print_header "1. Testing Prerequisites"
    
    print_test "Python version"
    if python --version | grep -q "3.1"; then
        print_success "Python 3.10+ found"
    else
        print_error "Python 3.10+ not found"
    fi

    print_test "Docker"
    if command -v docker &> /dev/null; then
        print_success "Docker found"
    else
        print_error "Docker not found"
    fi

    print_test "kubectl"
    if command -v kubectl &> /dev/null; then
        print_success "kubectl found"
    else
        print_error "kubectl not found (optional for local testing)"
    fi

    print_test "Helm"
    if command -v helm &> /dev/null; then
        print_success "Helm found"
    else
        print_error "Helm not found (optional for local testing)"
    fi

    # Test 2: Python Setup
    print_header "2. Testing Python Setup"
    
    print_test "Creating virtual environment"
    if [ ! -d ".venv" ]; then
        python -m venv .venv
        print_success "Virtual environment created"
    else
        print_info "Virtual environment already exists"
    fi

    print_test "Activating virtual environment"
    source .venv/bin/activate 2>/dev/null || source .venv/Scripts/activate 2>/dev/null
    print_success "Virtual environment activated"

    print_test "Installing dependencies"
    pip install -q --upgrade pip
    pip install -q -r requirements/base.txt -r requirements/dev.txt 2>/dev/null || {
        print_error "Failed to install dependencies"
        exit 1
    }
    print_success "Dependencies installed"

    print_test "Installing package"
    pip install -q -e . 2>/dev/null || {
        print_error "Failed to install package"
        exit 1
    }
    print_success "Package installed"

    # Test 3: Code Quality
    print_header "3. Testing Code Quality"
    
    print_test "Ruff linting"
    if ruff check . --quiet 2>/dev/null; then
        print_success "Ruff checks passed"
    else
        print_error "Ruff checks failed (run: ruff check . for details)"
    fi

    print_test "Black formatting"
    if black --check . --quiet 2>/dev/null; then
        print_success "Black formatting correct"
    else
        print_error "Black formatting issues (run: black . to fix)"
    fi

    # Test 4: Unit Tests
    print_header "4. Running Unit Tests"
    
    print_test "Pytest"
    if pytest tests/ -q 2>/dev/null; then
        print_success "All tests passed"
    else
        print_error "Some tests failed (run: pytest tests/ -v for details)"
    fi

    # Test 5: Docker Builds
    print_header "5. Testing Docker Builds"
    
    print_test "Building API Docker image"
    if docker build -f docker/Dockerfile.api -t churn-mlops-api:test . -q > /dev/null 2>&1; then
        print_success "API image built successfully"
    else
        print_error "API image build failed"
    fi

    print_test "Building ML Docker image"
    if docker build -f docker/Dockerfile.ml -t churn-mlops-ml:test . -q > /dev/null 2>&1; then
        print_success "ML image built successfully"
    else
        print_error "ML image build failed"
    fi

    # Test 6: Docker Runtime
    print_header "6. Testing Docker Runtime"
    
    print_test "Running API container"
    docker run -d --name test-api-container -p 8001:8000 churn-mlops-api:test > /dev/null 2>&1
    sleep 5

    print_test "API health check"
    if curl -sf http://localhost:8001/health > /dev/null 2>&1; then
        print_success "API responding to health checks"
    else
        print_error "API not responding (check: docker logs test-api-container)"
    fi

    print_test "Cleaning up container"
    docker stop test-api-container > /dev/null 2>&1
    docker rm test-api-container > /dev/null 2>&1
    print_success "Container cleaned up"

    # Test 7: Helm Charts (if Helm available)
    if command -v helm &> /dev/null; then
        print_header "7. Testing Helm Charts"
        
        print_test "Helm chart validation"
        if helm lint k8s/helm/churn-mlops/ --quiet; then
            print_success "Helm chart is valid"
        else
            print_error "Helm chart validation failed"
        fi

        print_test "Helm template rendering"
        if helm template churn-mlops k8s/helm/churn-mlops/ \
            --values k8s/helm/churn-mlops/values-staging.yaml \
            > /dev/null 2>&1; then
            print_success "Helm templates render correctly"
        else
            print_error "Helm template rendering failed"
        fi
    fi

    # Test 8: GitHub Workflows
    print_header "8. Checking GitHub Workflows"
    
    print_test "CI workflow exists"
    if [ -f ".github/workflows/ci.yml" ]; then
        print_success "CI workflow found"
    else
        print_error "CI workflow not found"
    fi

    print_test "CD workflow exists"
    if [ -f ".github/workflows/cd-build-push.yml" ]; then
        print_success "CD workflow found"
    else
        print_error "CD workflow not found"
    fi

    print_test "Release workflow exists"
    if [ -f ".github/workflows/release.yml" ]; then
        print_success "Release workflow found"
    else
        print_error "Release workflow not found"
    fi

    # Test 9: ArgoCD Manifests
    print_header "9. Checking ArgoCD Manifests"
    
    print_test "ArgoCD staging application"
    if [ -f "argocd/staging/application.yaml" ]; then
        print_success "Staging application manifest found"
    else
        print_error "Staging application manifest not found"
    fi

    print_test "ArgoCD production application"
    if [ -f "argocd/production/application.yaml" ]; then
        print_success "Production application manifest found"
    else
        print_error "Production application manifest not found"
    fi

    print_test "ArgoCD AppProject"
    if [ -f "argocd/appproject.yaml" ]; then
        print_success "AppProject manifest found"
    else
        print_error "AppProject manifest not found"
    fi

    # Test 10: Documentation
    print_header "10. Checking Documentation"
    
    for doc in "TESTING_GUIDE.md" "PRODUCTION_DEPLOYMENT.md" "GITOPS_WORKFLOW.md" "QUICK_REFERENCE.md"; do
        if [ -f "docs/$doc" ] || [ -f "$doc" ]; then
            print_success "$doc exists"
        else
            print_error "$doc not found"
        fi
    done

    # Summary
    print_header "Test Summary"
    echo ""
    echo -e "${GREEN}Tests Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Tests Failed: $TESTS_FAILED${NC}"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║   🎉 All Tests Passed! 🎉            ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${BLUE}Next Steps:${NC}"
        echo "1. Review TESTING_GUIDE.md for detailed testing"
        echo "2. Run: ./scripts/setup_production.sh (for Kubernetes setup)"
        echo "3. Commit and push to trigger GitHub Actions"
        echo "4. Deploy with ArgoCD"
        echo ""
    else
        echo -e "${RED}╔═══════════════════════════════════════╗${NC}"
        echo -e "${RED}║   ⚠️  Some Tests Failed              ║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════╝${NC}"
        echo ""
        echo "Please fix the failed tests before proceeding."
        echo "Check TESTING_GUIDE.md for troubleshooting."
        exit 1
    fi
}

# Run main function
main "$@"
