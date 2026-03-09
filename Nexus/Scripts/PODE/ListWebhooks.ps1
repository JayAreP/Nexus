# List all saved webhook configurations from nexus-webhooks container
try {
    $blobs = Get-BlobList -Container 'nexus-webhooks'
    $webhooks = @()
    foreach ($blob in $blobs) {
        if ($blob.Name -notmatch '\.json$') { continue }
        $content = Read-Blob -Container 'nexus-webhooks' -BlobPath $blob.Name
        if ($content) {
            $wh = $content | ConvertFrom-Json
            $webhooks += @{
                name     = $wh.name
                uri      = $wh.uri
                authType = $wh.authType
            }
        }
    }
    return @{ success = $true; webhooks = $webhooks }
} catch {
    return @{ success = $false; message = "Error listing webhooks: $($_.Exception.Message)"; webhooks = @() }
}
