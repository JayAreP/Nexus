# Clear log blobs older than N days for a specific workflow
param(
    [Parameter(Mandatory)] [string]$Workflow,
    [Parameter(Mandatory)] [int]$Days
)

$containerName = ($Workflow -replace '[^a-z0-9-]', '-').ToLower()
$cutoff = (Get-Date).AddDays(-$Days)

try {
    $ctx = Get-AppStorageContext
    $blobs = Get-AzStorageBlob -Container $containerName -Prefix 'logs/' -Context $ctx -ErrorAction Stop
    $removed = 0
    foreach ($blob in $blobs) {
        if ($blob.LastModified -lt $cutoff) {
            Remove-AzStorageBlob -Container $containerName -Blob $blob.Name -Context $ctx -Force -ErrorAction SilentlyContinue
            $removed++
        }
    }
    return @{ success = $true; message = "Removed $removed log(s) older than $Days days for '$Workflow'" }
} catch {
    return @{ success = $false; message = "Error clearing logs: $($_.Exception.Message)" }
}
