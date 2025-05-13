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

$imageName = "model-servers/ollama-server:$modelName-$modelTag"

Write-Host "Creating container with overridden entrypoint..."
$containerId = docker create `
    --entrypoint bash `
    $imageName `
    "-c" `
    "find /root/.ollama/models/blobs -type f -name sha256-* -size +1000000k -print -quit | grep -q . || exit 1"

Write-Host "Starting container to verify model presence..."
docker start -a $containerId

# Get the exit code from the container
$exitCode = docker inspect $containerId --format='{{.State.ExitCode}}'

# Clean up the container
docker rm $containerId | Out-Null

if ($exitCode -ne 0) {
    Write-Host "No file larger than 1GB found. Exiting with error." -ForegroundColor Red
    exit 1
} else {
    Write-Host "File larger than 1GB found. Success." -ForegroundColor Green
}