# Ensure PSGallery is trusted
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue

# Install powershell-yaml if missing
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Install-Module -Name powershell-yaml -Force -Scope CurrentUser
}

Import-Module powershell-yaml


# Convert model_size (e.g., "1.1GiB") to kilobytes for find -size
function Convert-GiBToKilobytes($sizeString) {
    if ($sizeString -match '^([\d\.]+)GiB$') {
        $number = [double]$matches[1]
        return [int]($number * 1024 * 1024)
    } elseif ($sizeString -match '^([\d\.]+)\s*(MiB|MB)$') {
        $number = [double]$matches[1]
        return [int]($number * 1024)
    } else {
        throw "Invalid model_size format: $sizeString"
    }
}

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
$manifestPath = "/root/.ollama/models/manifests/registry.ollama.ai/library/$modelName/$modelTag"
$modelSizeKB = Convert-GiBToKilobytes $modelSize
$expectedFileSizeKB = [int]($modelSizeKB / 2)

Write-Host "Creating container with overridden entrypoint..."
$containerId = docker create `
    --entrypoint bash `
    $imageName `
    "-c" `
    "find /root/.ollama/models/blobs -type f -name sha256-* -size +${expectedFileSizeKB}k -print -quit | grep -q . && test -f '$manifestPath'"

Write-Host "Starting container to verify model presence..."
docker start -a $containerId

# Get the exit code from the container
$exitCode = docker inspect $containerId --format='{{.State.ExitCode}}'

# Clean up the container
docker rm $containerId | Out-Null

if ($exitCode -ne 0) {
    Write-Host "No file larger than $modelSize found. Exiting with error." -ForegroundColor Red
    exit 1
} else {
    Write-Host "File larger than $modelSize found. Success." -ForegroundColor Green
}

Write-Host "Creating container to verify gpu.json existence and content..."
$gpuMetricsCheckContainerId = docker create `
    --entrypoint bash `
    $imageName `
    "-c" `
    "test -s /metrics/gpu.json"

Write-Host "Starting container to check gpu.json..."
docker start -a $gpuMetricsCheckContainerId

# Get the exit code
$gpuMetricsExitCode = docker inspect $gpuMetricsCheckContainerId --format='{{.State.ExitCode}}'

# Clean up the container
docker rm $gpuMetricsCheckContainerId | Out-Null

if ($gpuMetricsExitCode -ne 0) {
    Write-Host "/metrics/gpu.json is missing or empty. Exiting with error." -ForegroundColor Red
    exit 1
} else {
    Write-Host "/metrics/gpu.json exists and is not empty." -ForegroundColor Green
}
