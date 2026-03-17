# Upload a script to a storage container
param(
    [Parameter(Mandatory)] [string]$Container,
    [Parameter(Mandatory)] [string]$FileName,
    [Parameter(Mandatory)] [string]$FilePath
)

if (-not (Test-Path $FilePath)) {
    return @{ success = $false; message = "Uploaded file not found"; statusCode = 400 }
}

try {
    $ctx = Get-AppStorageContext
    Set-AzStorageBlobContent -Container $Container -Blob $FileName -File $FilePath -Context $ctx -Force | Out-Null
    return @{ success = $true; message = "Script '$FileName' uploaded successfully" }
} catch {
    return @{ success = $false; message = "Upload error: $($_.Exception.Message)"; statusCode = 500 }
}
