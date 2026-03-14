<#
.SYNOPSIS
    Builds and publishes the Nexus container image to GitHub Container Registry (ghcr.io).

.DESCRIPTION
    Authenticates with ghcr.io, builds the Docker image with version tagging,
    and pushes it to the specified GitHub user's container registry.

.PARAMETER GitHubUser
    Your GitHub username (lowercase). Used as the registry namespace.

.PARAMETER Token
    A GitHub Personal Access Token (classic) with the required permissions.

.PARAMETER ImageName
    The container image name. Defaults to 'nexus'.

.PARAMETER Tag
    Optional version tag. Defaults to a timestamp (yyyyMMdd-HHmmss).
    The image is always also tagged as 'latest'.

.PARAMETER SkipLatest
    If set, only pushes the versioned tag and skips the 'latest' tag.

.EXAMPLE
    ./publishContainer.ps1 -GitHubUser myuser -Token ghp_xxxxxxxxxxxx

.EXAMPLE
    ./publishContainer.ps1 -GitHubUser myuser -Token ghp_xxxxxxxxxxxx -Tag "1.0.0"

.NOTES
    ============================================================
    GITHUB TOKEN PERMISSIONS REQUIRED (Personal Access Token - Classic)
    ============================================================
    Go to: GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)

    Required scopes:
      - write:packages    Push packages to GitHub Container Registry
      - read:packages     Pull packages (included in write:packages)
      - delete:packages   (optional) Delete old package versions

    The token must be a "Classic" PAT. Fine-grained tokens do NOT
    support ghcr.io at this time.
    ============================================================
#>
param(
    [Parameter(Mandatory)] [string]$GitHubUser,
    [Parameter(Mandatory)] [string]$Token,
    [string]$ImageName = 'nexus',
    [string]$Tag,
    [switch]$SkipLatest
)

$ErrorActionPreference = 'Stop'

# Default tag to timestamp
if ([string]::IsNullOrWhiteSpace($Tag)) {
    $Tag = (Get-Date).ToString('yyyyMMdd-HHmmss')
}

# Normalize GitHub username to lowercase (ghcr.io requires it)
$GitHubUser = $GitHubUser.ToLower()

$registry = 'ghcr.io'
$fullImage = "$registry/$GitHubUser/$ImageName"

Write-Host "`n=== Nexus Container Publish ===" -ForegroundColor Cyan
Write-Host "Registry:  $registry" -ForegroundColor Gray
Write-Host "Image:     $fullImage" -ForegroundColor Gray
Write-Host "Tag:       $Tag" -ForegroundColor Gray
Write-Host ""

# Step 1: Authenticate with ghcr.io
Write-Host "[1/4] Authenticating with $registry..." -ForegroundColor Yellow
$Token | docker login $registry -u $GitHubUser --password-stdin
if ($LASTEXITCODE -ne 0) {
    Write-Host "Authentication failed." -ForegroundColor Red
    exit 1
}
Write-Host "Authenticated." -ForegroundColor Green

# Step 2: Write version tag to version.txt so the build embeds it
Write-Host "[2/5] Writing version ($Tag) to version.txt..." -ForegroundColor Yellow
$Tag | Set-Content -Path (Join-Path $PSScriptRoot 'version.txt') -NoNewline

# Step 3: Update deploy compose with correct image reference
Write-Host "[3/5] Updating docker-compose.deploy.yml..." -ForegroundColor Yellow
$deployFile = Join-Path $PSScriptRoot 'docker-compose.deploy.yml'
if (Test-Path $deployFile) {
    $content = Get-Content $deployFile -Raw
    $content = $content -replace 'image: ghcr\.io/.+/nexus:.+', "image: ${fullImage}:latest"
    Set-Content -Path $deployFile -Value $content -NoNewline
    Write-Host "Deploy compose updated." -ForegroundColor Green
}

# Step 4: Build the image
Write-Host "[4/5] Building image ${fullImage}:${Tag}..." -ForegroundColor Yellow
$buildArgs = @(
    'build',
    '-t', "${fullImage}:${Tag}"
)
if (-not $SkipLatest) {
    $buildArgs += '-t'
    $buildArgs += "${fullImage}:latest"
}
$buildArgs += $PSScriptRoot

& docker @buildArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed." -ForegroundColor Red
    exit 1
}
Write-Host "Build complete." -ForegroundColor Green

# Step 5: Push to registry
Write-Host "[5/5] Pushing to $registry..." -ForegroundColor Yellow
docker push "${fullImage}:${Tag}"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Push failed for tag '$Tag'." -ForegroundColor Red
    exit 1
}

if (-not $SkipLatest) {
    docker push "${fullImage}:latest"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Push failed for tag 'latest'." -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n=== Published successfully ===" -ForegroundColor Green
Write-Host "  ${fullImage}:${Tag}" -ForegroundColor Green
if (-not $SkipLatest) {
    Write-Host "  ${fullImage}:latest" -ForegroundColor Green
}
Write-Host ""
Write-Host "Pull command:" -ForegroundColor Gray
Write-Host "  docker pull ${fullImage}:${Tag}" -ForegroundColor White
Write-Host ""
Write-Host "Deploy on a new host:" -ForegroundColor Gray
Write-Host "  1. Copy docker-compose.deploy.yml and .env.example to the host" -ForegroundColor White
Write-Host "  2. Rename .env.example to .env and fill in credentials" -ForegroundColor White
Write-Host "  3. mkdir conf" -ForegroundColor White
Write-Host "  4. docker compose -f docker-compose.deploy.yml up -d" -ForegroundColor White
Write-Host ""
