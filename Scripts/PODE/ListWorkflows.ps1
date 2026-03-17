# List all saved workflows from nexus-config/workflows/
try {
    $blobs = Get-BlobList -Container 'nexus-config' -Prefix 'workflows/'
    $workflows = @()
    foreach ($blob in $blobs) {
        if ($blob.Name -notmatch '\.json$') { continue }
        $content = Read-Blob -Container 'nexus-config' -BlobPath $blob.Name
        if ($content) {
            $wf = $content | ConvertFrom-Json
            $stepCount = 0
            if ($wf.steps) { $stepCount = @($wf.steps).Count }
            $workflows += @{
                name      = $wf.name
                stepCount = $stepCount
            }
        }
    }
    return @{ success = $true; workflows = $workflows }
} catch {
    return @{ success = $false; message = "Error listing workflows: $($_.Exception.Message)"; workflows = @() }
}
