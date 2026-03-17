# List run logs for a workflow from {workflow-container}/logs/
param(
    [Parameter(Mandatory)] [string]$Workflow
)

$containerName = ($Workflow -replace '[^a-z0-9-]', '-').ToLower()

try {
    $blobs = Get-BlobList -Container $containerName -Prefix 'logs/'
    $logs = @()
    foreach ($blob in $blobs) {
        if ($blob.Name -notmatch '\.(json|log)$') { continue }
        $logs += @{
            name         = $blob.Name -replace '^logs/', ''
            lastModified = $blob.LastModified.ToString('yyyy-MM-dd HH:mm:ss')
        }
    }
    # Sort newest first (by name which contains timestamp)
    $logs = @($logs | Sort-Object { $_.lastModified } -Descending)
    return @{ success = $true; logs = $logs }
} catch {
    return @{ success = $false; message = "Error listing logs: $($_.Exception.Message)"; logs = @() }
}
