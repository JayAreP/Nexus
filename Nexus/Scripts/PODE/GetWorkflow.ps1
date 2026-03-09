# Get a single workflow definition
param(
    [Parameter(Mandatory)] [string]$Name
)

try {
    $content = Read-Blob -Container 'nexus-config' -BlobPath "workflows/$Name.json"
    if (-not $content) {
        return @{ success = $false; message = "Workflow '$Name' not found"; statusCode = 404 }
    }
    $workflow = $content | ConvertFrom-Json
    return @{ success = $true; workflow = $workflow }
} catch {
    return @{ success = $false; message = "Error loading workflow: $($_.Exception.Message)"; statusCode = 500 }
}
