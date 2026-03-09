# Copy Nexus app to GitHub repository folder

$sourceFolder = 'C:\Users\Jar\Dropbox\jsnew\Nexus'
$destinationFolder = 'C:\Users\Jar\Dropbox\_GitHub\Nexus\Nexus'

# Create destination if it doesn't exist
if (-not (Test-Path $destinationFolder)) {
    New-Item -Path $destinationFolder -ItemType Directory -Force | Out-Null
    Write-Host "Created destination folder: $destinationFolder" -ForegroundColor Green
}

# Copy all items from source to destination
try {
    Copy-Item -Path "$sourceFolder\*" -Destination $destinationFolder -Recurse -Force
    Write-Host "Successfully copied all items from $sourceFolder to $destinationFolder" -ForegroundColor Green
} catch {
    Write-Host "Error during copy: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`nCopy complete!" -ForegroundColor Green
