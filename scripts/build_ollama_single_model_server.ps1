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

New-Item -ItemType Directory -Path "ollama\model-cache" -Force | Out-Null
$cachePath = Resolve-Path "ollama\model-cache"
if (Test-Path "ollama\model-cache") {
    Remove-Item -Path "ollama\model-cache\*" -Recurse -Force
}

docker run --rm `
    --entrypoint sh `
    -v "$($cachePath.Path):/root/.ollama" `
    -e OLLAMA_ORCHESTRATOR=standalone `
    ollama/ollama:0.6.5 `
    -c "ollama serve & sleep 5 && ollama pull ${modelName}:${modelTag}"

# Get current date in yyyy-MM-dd format
$date = Get-Date -Format "yyyy-MM-dd"

# Docker build command (multiline for readability)
docker build --no-cache `
    --build-arg MODEL_NAME=$modelName `
    --build-arg MODEL_TAG=$modelTag `
    --build-arg LICENSE=$license `
    --build-arg MODEL_SIZE=$modelSize `
    --build-arg MEMORY_MIN=$memMin `
    --build-arg MEMORY_RECOMMENDED=$memRecommended `
    --tag model-servers/ollama-server:$modelName-$modelTag `
    --label org.opencontainers.image.title="Ollama Server - $modelName" `
    --label org.opencontainers.image.description="Preloaded Ollama model server for ${modelName}:${modelTag}" `
    --label org.opencontainers.image.version="$modelName-$modelTag" `
    --label org.opencontainers.image.authors="Sinan Ozel" `
    --label org.opencontainers.image.licenses=$license `
    --label org.opencontainers.image.vendor="sinanozel" `
    --label org.opencontainers.image.memory.size=$modelSize `
    --label org.opencontainers.image.memory.min=$memMin `
    --label org.opencontainers.image.memory.recommended=$memRecommended `
    --label org.opencontainers.image.date=$date `
    --file ./ollama/Dockerfile ./ollama

Remove-Item -Path "ollama\model-cache\*" -Recurse -Force