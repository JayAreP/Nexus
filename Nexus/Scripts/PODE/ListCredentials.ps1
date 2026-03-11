# List all saved credentials from nexus-credentials container (metadata only, no secrets)
try {
    $blobs = Get-BlobList -Container 'nexus-credentials'
    $credentials = @()
    foreach ($blob in $blobs) {
        if ($blob.Name -notmatch '\.json$') { continue }
        $content = Read-Blob -Container 'nexus-credentials' -BlobPath $blob.Name
        if ($content) {
            $cred = $content | ConvertFrom-Json
            $credentials += @{
                name        = $cred.name
                type        = $cred.type
                description = $cred.description
                created     = $cred.created
                modified    = $cred.modified
            }
        }
    }
    return @{ success = $true; credentials = $credentials }
} catch {
    return @{ success = $false; message = "Error listing credentials: $($_.Exception.Message)"; credentials = @() }
}
