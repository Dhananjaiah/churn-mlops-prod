# Quick Test Script for Windows PowerShell
# Run: .\scripts\quick_test.ps1

$ErrorActionPreference = "Continue"
$TestsPassed = 0
$TestsFailed = 0

# Helper functions
function Print-Header {
    param($Message)
    Write-Host "`n========================================" -ForegroundColor Blue
    Write-Host $Message -ForegroundColor Blue
    Write-Host "========================================" -ForegroundColor Blue
}

function Print-Test {
    param($Message)
    Write-Host "Testing: $Message" -ForegroundColor Yellow
}

function Print-Success {
    param($Message)
    Write-Host "✅ $Message" -ForegroundColor Green
    $script:TestsPassed++
}

function Print-Error {
    param($Message)
    Write-Host "❌ $Message" -ForegroundColor Red
    $script:TestsFailed++
}

function Print-Info {
    param($Message)
    Write-Host "ℹ️  $Message" -ForegroundColor Cyan
}

# Main
Write-Host "╔═══════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║   Churn MLOps Quick Test Script      ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════╝" -ForegroundColor Green

# Test 1: Prerequisites
Print-Header "1. Testing Prerequisites"

Print-Test "Python version"
try {
    $pythonVersion = python --version 2>&1
    if ($pythonVersion -match "3\.1\d") {
        Print-Success "Python 3.10+ found: $pythonVersion"
    } else {
        Print-Error "Python 3.10+ not found"
    }
} catch {
    Print-Error "Python not found"
}

Print-Test "Docker"
if (Get-Command docker -ErrorAction SilentlyContinue) {
    Print-Success "Docker found"
} else {
    Print-Error "Docker not found"
}

Print-Test "kubectl"
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    Print-Success "kubectl found"
} else {
    Print-Error "kubectl not found (optional for local testing)"
}

Print-Test "Helm"
if (Get-Command helm -ErrorAction SilentlyContinue) {
    Print-Success "Helm found"
} else {
    Print-Error "Helm not found (optional for local testing)"
}

# Test 2: Python Setup
Print-Header "2. Testing Python Setup"

Print-Test "Creating virtual environment"
if (-not (Test-Path ".venv")) {
    python -m venv .venv
    Print-Success "Virtual environment created"
} else {
    Print-Info "Virtual environment already exists"
}

Print-Test "Activating virtual environment"
& .\.venv\Scripts\Activate.ps1
Print-Success "Virtual environment activated"

Print-Test "Installing dependencies"
python -m pip install -q --upgrade pip
python -m pip install -q -r requirements/base.txt -r requirements/dev.txt 2>$null
if ($LASTEXITCODE -eq 0) {
    Print-Success "Dependencies installed"
} else {
    Print-Error "Failed to install dependencies"
}

Print-Test "Installing package"
python -m pip install -q -e . 2>$null
if ($LASTEXITCODE -eq 0) {
    Print-Success "Package installed"
} else {
    Print-Error "Failed to install package"
}

# Test 3: Code Quality
Print-Header "3. Testing Code Quality"

Print-Test "Ruff linting"
ruff check . --quiet 2>$null
if ($LASTEXITCODE -eq 0) {
    Print-Success "Ruff checks passed"
} else {
    Print-Error "Ruff checks failed (run: ruff check . for details)"
}

Print-Test "Black formatting"
black --check . --quiet 2>$null
if ($LASTEXITCODE -eq 0) {
    Print-Success "Black formatting correct"
} else {
    Print-Error "Black formatting issues (run: black . to fix)"
}

# Test 4: Unit Tests
Print-Header "4. Running Unit Tests"

Print-Test "Pytest"
pytest tests/ -q 2>$null
if ($LASTEXITCODE -eq 0) {
    Print-Success "All tests passed"
} else {
    Print-Error "Some tests failed (run: pytest tests/ -v for details)"
}

# Test 5: Docker Builds
Print-Header "5. Testing Docker Builds"

Print-Test "Building API Docker image"
docker build -f docker/Dockerfile.api -t churn-mlops-api:test . -q 2>$null
if ($LASTEXITCODE -eq 0) {
    Print-Success "API image built successfully"
} else {
    Print-Error "API image build failed"
}

Print-Test "Building ML Docker image"
docker build -f docker/Dockerfile.ml -t churn-mlops-ml:test . -q 2>$null
if ($LASTEXITCODE -eq 0) {
    Print-Success "ML image built successfully"
} else {
    Print-Error "ML image build failed"
}

# Test 6: Docker Runtime
Print-Header "6. Testing Docker Runtime"

Print-Test "Running API container"
docker run -d --name test-api-container -p 8001:8000 churn-mlops-api:test 2>$null
Start-Sleep -Seconds 5

Print-Test "API health check"
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8001/health" -UseBasicParsing -TimeoutSec 5
    if ($response.StatusCode -eq 200) {
        Print-Success "API responding to health checks"
    } else {
        Print-Error "API returned status code: $($response.StatusCode)"
    }
} catch {
    Print-Error "API not responding (check: docker logs test-api-container)"
}

Print-Test "Cleaning up container"
docker stop test-api-container 2>$null
docker rm test-api-container 2>$null
Print-Success "Container cleaned up"

# Test 7: Helm Charts
if (Get-Command helm -ErrorAction SilentlyContinue) {
    Print-Header "7. Testing Helm Charts"
    
    Print-Test "Helm chart validation"
    helm lint k8s/helm/churn-mlops/ --quiet 2>$null
    if ($LASTEXITCODE -eq 0) {
        Print-Success "Helm chart is valid"
    } else {
        Print-Error "Helm chart validation failed"
    }

    Print-Test "Helm template rendering"
    helm template churn-mlops k8s/helm/churn-mlops/ --values k8s/helm/churn-mlops/values-staging.yaml 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Print-Success "Helm templates render correctly"
    } else {
        Print-Error "Helm template rendering failed"
    }
}

# Test 8: GitHub Workflows
Print-Header "8. Checking GitHub Workflows"

Print-Test "CI workflow exists"
if (Test-Path ".github/workflows/ci.yml") {
    Print-Success "CI workflow found"
} else {
    Print-Error "CI workflow not found"
}

Print-Test "CD workflow exists"
if (Test-Path ".github/workflows/cd-build-push.yml") {
    Print-Success "CD workflow found"
} else {
    Print-Error "CD workflow not found"
}

Print-Test "Release workflow exists"
if (Test-Path ".github/workflows/release.yml") {
    Print-Success "Release workflow found"
} else {
    Print-Error "Release workflow not found"
}

# Test 9: ArgoCD Manifests
Print-Header "9. Checking ArgoCD Manifests"

Print-Test "ArgoCD staging application"
if (Test-Path "argocd/staging/application.yaml") {
    Print-Success "Staging application manifest found"
} else {
    Print-Error "Staging application manifest not found"
}

Print-Test "ArgoCD production application"
if (Test-Path "argocd/production/application.yaml") {
    Print-Success "Production application manifest found"
} else {
    Print-Error "Production application manifest not found"
}

Print-Test "ArgoCD AppProject"
if (Test-Path "argocd/appproject.yaml") {
    Print-Success "AppProject manifest found"
} else {
    Print-Error "AppProject manifest not found"
}

# Test 10: Documentation
Print-Header "10. Checking Documentation"

$docs = @("TESTING_GUIDE.md", "PRODUCTION_DEPLOYMENT.md", "GITOPS_WORKFLOW.md", "QUICK_REFERENCE.md")
foreach ($doc in $docs) {
    if ((Test-Path "docs/$doc") -or (Test-Path $doc)) {
        Print-Success "$doc exists"
    } else {
        Print-Error "$doc not found"
    }
}

# Summary
Print-Header "Test Summary"
Write-Host ""
Write-Host "Tests Passed: $TestsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $TestsFailed" -ForegroundColor Red
Write-Host ""

if ($TestsFailed -eq 0) {
    Write-Host "╔═══════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║   🎉 All Tests Passed! 🎉            ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "1. Review TESTING_GUIDE.md for detailed testing"
    Write-Host "2. Run: .\scripts\setup_production.sh (for Kubernetes setup)"
    Write-Host "3. Commit and push to trigger GitHub Actions"
    Write-Host "4. Deploy with ArgoCD"
    Write-Host ""
} else {
    Write-Host "╔═══════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║   ⚠️  Some Tests Failed              ║" -ForegroundColor Red
    Write-Host "╚═══════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please fix the failed tests before proceeding."
    Write-Host "Check TESTING_GUIDE.md for troubleshooting."
    exit 1
}
