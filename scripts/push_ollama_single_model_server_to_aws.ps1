# Ensure PSGallery is trusted
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue

# Install powershell-yaml if missing
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Install-Module -Name powershell-yaml -Force -Scope CurrentUser
}

Import-Module powershell-yaml

# Get YAML file path
$ModelFile = $args[0]

# Read and parse YAML
$yamlContent = Get-Content $ModelFile -Raw
$yaml = ConvertFrom-Yaml $yamlContent

# Extract scalar values safely
$modelName = $yaml.name
$modelTag = $yaml.tag
$license = $yaml.license
$modelSize = $yaml.memory.model_size
$memMin = $yaml.memory.min
$memRecommended = $yaml.memory.recommended

# AWS region from environment variable or fallback
$awsRegion = $env:AWS_REGION
if (-not $awsRegion) {
    Write-Host "Environment variable AWS_REGION is not set. Exiting." -ForegroundColor Red
    exit 1
}

# Get AWS account ID
$accountId = aws sts get-caller-identity --query 'Account' --output text
$hostname = "$accountId.dkr.ecr.$awsRegion.amazonaws.com"
$repositoryName = "model-servers/ollama-server"

# Login to ECR
Write-Host "Logging into AWS ECR..."
aws ecr get-login-password --region $awsRegion | docker login --username AWS --password-stdin $hostname

# Ensure repository exists
Write-Host "Ensuring repository $repositoryName exists..."
$repoExists = aws ecr describe-repositories --repository-names $repositoryName --region $awsRegion -ErrorAction SilentlyContinue

if (-not $repoExists) {
    Write-Host "Repository does not exist. Creating..."
    aws ecr create-repository --repository-name $repositoryName --region $awsRegion | Out-Null
} else {
    Write-Host "Repository exists."
}

# Tag the Docker image
$localImage = "model-servers/ollama-server:$modelName-$modelTag"
$remoteImage = "$hostname/${repositoryName}:$modelName-$modelTag"

Write-Host "Tagging image $localImage as $remoteImage..."
docker tag $localImage $remoteImage

# Push the Docker image
Write-Host "Pushing image to ECR..."
docker push $remoteImage
