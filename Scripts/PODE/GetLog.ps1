# Get a specific run log file
param(
    [Parameter(Mandatory)] [string]$Workflow,
    [Parameter(Mandatory)] [string]$LogName
)

$containerName = ($Workflow -replace '[^a-z0-9-]', '-').ToLower()

try {
    $content = Read-Blob -Container $containerName -BlobPath "logs/$LogName"
    if (-not $content) {
        return @{ success = $false; message = "Log '$LogName' not found"; statusCode = 404 }
    }
    # JSON logs get parsed, plain text logs (.log) returned as-is
    if ($LogName -match '\.json$') {
        $log = $content | ConvertFrom-Json
        return @{ success = $true; log = $log }
    } else {
        return @{ success = $true; log = $content }
    }
} catch {
    return @{ success = $false; message = "Error loading log: $($_.Exception.Message)"; statusCode = 500 }
}
