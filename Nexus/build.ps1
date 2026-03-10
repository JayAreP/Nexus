# Build Nexus app with timestamp as version tag

$version = (Get-Date).ToString('yyyyMMdd-HHmmss')

# Write version to file for Dockerfile to COPY
$version | Set-Content -Path './version.txt' -NoNewline

Write-Host "Building Nexus v$version..." -ForegroundColor Cyan

docker-compose down 2>$null
docker-compose up -d --build

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nBuild successful!" -ForegroundColor Green
    Write-Host "Version: $version" -ForegroundColor Green
    Write-Host "App running at http://localhost:8082" -ForegroundColor Green
} else {
    Write-Host "Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit 1
}
