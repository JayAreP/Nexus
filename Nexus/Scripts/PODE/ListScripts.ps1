# List scripts in a given storage container
param(
    [Parameter(Mandatory)] [string]$Container
)

try {
    $blobs = Get-BlobList -Container $Container
    $scripts = @()
    foreach ($blob in $blobs) {
        $scripts += @{
            name         = $blob.Name
            lastModified = $blob.LastModified.ToString('yyyy-MM-dd HH:mm:ss')
            size         = $blob.Length
        }
    }
    return @{ success = $true; scripts = $scripts }
} catch {
    return @{ success = $false; message = "Error listing scripts: $($_.Exception.Message)"; scripts = @() }
}
