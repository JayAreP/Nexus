# Delete a workflow definition and optionally its container
param(
    [Parameter(Mandatory)] [string]$Name
)

try {
    Remove-Blob -Container 'nexus-config' -BlobPath "workflows/$Name.json"
    return @{ success = $true; message = "Workflow '$Name' deleted" }
} catch {
    return @{ success = $false; message = "Error deleting workflow: $($_.Exception.Message)"; statusCode = 500 }
}
