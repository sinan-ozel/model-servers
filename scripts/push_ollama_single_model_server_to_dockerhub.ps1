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

# Docker Hub namespace
$dockerHubNamespace = $env:DOCKERHUB_NAMESPACE
if (-not $dockerHubNamespace) {
    Write-Host "Environment variable DOCKERHUB_NAMESPACE is not set. Exiting." -ForegroundColor Red
    exit 1
}

# Login to Docker Hub (interactive if not already logged in)
Write-Host "Logging in to Docker Hub..."
docker login

# Local and remote tags
$localImage = "model-servers/ollama-server:$modelName-$modelTag"
$remoteImage = "$dockerHubNamespace/ollama-server:$modelName-$modelTag"

# Tag the image
Write-Host "Tagging image $localImage as $remoteImage..."
docker tag $localImage $remoteImage

# Push the image
Write-Host "Pushing image to Docker Hub..."
docker push $remoteImage
