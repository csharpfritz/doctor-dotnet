#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds the CodeMedic Docker container with versioning from Nerd Bank Git Versioning.

.DESCRIPTION
    This script builds a Docker container for CodeMedic, automatically retrieving
    the version number from NBGv2 and tagging the container appropriately.

.PARAMETER Registry
    Optional Docker registry prefix (e.g., "docker.io/username" or "ghcr.io/owner")

.PARAMETER Push
    If specified, pushes the built image to the registry

.PARAMETER BuildConfiguration
    Build configuration (Release or Debug). Default is Release.

.EXAMPLE
    .\build-docker.ps1
    Builds the container locally with version tags

.EXAMPLE
    .\build-docker.ps1 -Registry "ghcr.io/csharpfritz" -Push
    Builds and pushes to GitHub Container Registry
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Registry = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$Push,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('Release', 'Debug')]
    [string]$BuildConfiguration = 'Release'
)

$ErrorActionPreference = 'Stop'

Write-Host "🏥 CodeMedic Docker Build Script" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan
Write-Host ""

# Ensure we're in the repository root
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptPath

# Check if Docker is available
try {
    docker --version | Out-Null
} catch {
    Write-Error "Docker is not installed or not in PATH. Please install Docker first."
    exit 1
}

# Check if nbgv is available, if not install it
$nbgvInstalled = Get-Command nbgv -ErrorAction SilentlyContinue
if (-not $nbgvInstalled) {
    Write-Host "📦 Installing Nerd Bank Git Versioning CLI tool..." -ForegroundColor Yellow
    dotnet tool install -g nbgv
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to install nbgv. Please install it manually: dotnet tool install -g nbgv"
        exit 1
    }
}

# Get version information from NBGv2
Write-Host "🔢 Retrieving version information from NBGv2..." -ForegroundColor Green
$versionJson = nbgv get-version -f json | ConvertFrom-Json

if (-not $versionJson) {
    Write-Error "Failed to retrieve version information from NBGv2"
    exit 1
}

$version = $versionJson.Version
$semVer2 = $versionJson.SemVer2
$assemblyVersion = $versionJson.AssemblyVersion
$fileVersion = $versionJson.AssemblyFileVersion
$informationalVersion = $versionJson.AssemblyInformationalVersion
$majorMinor = "$($versionJson.VersionMajor).$($versionJson.VersionMinor)"
$commit = $versionJson.GitCommitIdShort

Write-Host "  Version: $version" -ForegroundColor White
Write-Host "  SemVer2: $semVer2" -ForegroundColor White
Write-Host "  Assembly Version: $assemblyVersion" -ForegroundColor White
Write-Host "  File Version: $fileVersion" -ForegroundColor White
Write-Host "  Informational: $informationalVersion" -ForegroundColor White
Write-Host "  Commit:  $commit" -ForegroundColor White
Write-Host ""

# Construct image name
$imageName = "codemedic"
if ($Registry) {
    $imageName = "$Registry/$imageName"
}

# Build tags
$tags = @(
    "${imageName}:${semVer2}",
    "${imageName}:${majorMinor}",
    "${imageName}:latest"
)

# Add commit-specific tag for tracking
$tags += "${imageName}:${semVer2}-${commit}"

Write-Host "🐳 Building Docker image..." -ForegroundColor Green
Write-Host "  Image name: $imageName" -ForegroundColor White
Write-Host "  Tags:" -ForegroundColor White
foreach ($tag in $tags) {
    Write-Host "    - $tag" -ForegroundColor White
}
Write-Host ""

# Build the Docker image
$dockerBuildArgs = @(
    "build",
    "-f", "Dockerfile",
    "--build-arg", "BUILD_CONFIGURATION=$BuildConfiguration",
    "--build-arg", "VERSION=$semVer2",
    "--build-arg", "ASSEMBLY_VERSION=$assemblyVersion",
    "--build-arg", "FILE_VERSION=$fileVersion",
    "--build-arg", "INFORMATIONAL_VERSION=$informationalVersion"
)

# Add all tags
foreach ($tag in $tags) {
    $dockerBuildArgs += "-t"
    $dockerBuildArgs += $tag
}

$dockerBuildArgs += "."

Write-Host "🔨 Executing: docker $($dockerBuildArgs -join ' ')" -ForegroundColor Gray
& docker $dockerBuildArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker build failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "✅ Docker image built successfully!" -ForegroundColor Green
Write-Host ""

# Push if requested
if ($Push) {
    if (-not $Registry) {
        Write-Error "Cannot push without specifying a registry. Use -Registry parameter."
        exit 1
    }
    
    Write-Host "📤 Pushing images to registry..." -ForegroundColor Green
    foreach ($tag in $tags) {
        Write-Host "  Pushing: $tag" -ForegroundColor White
        docker push $tag
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to push $tag"
            exit $LASTEXITCODE
        }
    }
    
    Write-Host ""
    Write-Host "✅ All images pushed successfully!" -ForegroundColor Green
    Write-Host ""
}

# Display usage examples
Write-Host "📋 Usage Examples:" -ForegroundColor Cyan
Write-Host "  Run health check:" -ForegroundColor White
Write-Host "    docker run --rm -v `${PWD}:/repo $($tags[0]) health /repo" -ForegroundColor Gray
Write-Host ""
Write-Host "  Show help:" -ForegroundColor White
Write-Host "    docker run --rm $($tags[0]) --help" -ForegroundColor Gray
Write-Host ""
Write-Host "  Interactive shell:" -ForegroundColor White
Write-Host "    docker run --rm -it --entrypoint /bin/bash $($tags[0])" -ForegroundColor Gray
Write-Host ""
