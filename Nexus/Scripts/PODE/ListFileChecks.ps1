# List all saved file check configurations from nexus-config/filechecks/
try {
    $blobs = Get-BlobList -Container 'nexus-config' -Prefix 'filechecks/'
    $filechecks = @()
    foreach ($blob in $blobs) {
        if ($blob.Name -notmatch '\.json$') { continue }
        $content = Read-Blob -Container 'nexus-config' -BlobPath $blob.Name
        if ($content) {
            $fc = $content | ConvertFrom-Json
            $filechecks += @{
                name           = $fc.name
                storageAccount = $fc.storageAccount
                authType       = $fc.authType
            }
        }
    }
    return @{ success = $true; filechecks = $filechecks }
} catch {
    return @{ success = $false; message = "Error listing file checks: $($_.Exception.Message)"; filechecks = @() }
}
