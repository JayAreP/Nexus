# Save a workflow definition to nexus-config/workflows/
param(
    [Parameter(Mandatory)] [string]$WorkflowJson
)

try {
    $workflow = $WorkflowJson | ConvertFrom-Json

    if ([string]::IsNullOrWhiteSpace($workflow.name)) {
        return @{ success = $false; message = "Workflow name is required"; statusCode = 400 }
    }

    # Ensure the per-workflow container exists for future logs
    $ctx = Get-AppStorageContext
    $containerName = ($workflow.name -replace '[^a-z0-9-]', '-').ToLower()
    $existing = Get-AzStorageContainer -Name $containerName -Context $ctx -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-AzStorageContainer -Name $containerName -Context $ctx -Permission Off -ErrorAction SilentlyContinue | Out-Null
    }

    Write-Blob -Container 'nexus-config' -BlobPath "workflows/$($workflow.name).json" -Content $WorkflowJson

    return @{ success = $true; message = "Workflow '$($workflow.name)' saved" }
} catch {
    return @{ success = $false; message = "Error saving workflow: $($_.Exception.Message)"; statusCode = 500 }
}
