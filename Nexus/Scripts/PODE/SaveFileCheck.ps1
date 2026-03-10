# Save a file check configuration to nexus-config/filechecks/
param(
    [Parameter(Mandatory)] [string]$Name,
    [Parameter(Mandatory)] [string]$StorageAccount,
    [Parameter(Mandatory)] [string]$AuthType,
    [string]$SasToken = ''
)

if ([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($StorageAccount)) {
    return @{ success = $false; message = "Name and Storage Account are required"; statusCode = 400 }
}

if ($AuthType -eq 'sas' -and [string]::IsNullOrWhiteSpace($SasToken)) {
    return @{ success = $false; message = "SAS token is required when auth type is SAS"; statusCode = 400 }
}

try {
    $filecheck = @{
        name           = $Name
        storageAccount = $StorageAccount
        authType       = $AuthType
        sasToken       = $SasToken
    }

    $json = $filecheck | ConvertTo-Json -Depth 5
    Write-Blob -Container 'nexus-config' -BlobPath "filechecks/$Name.json" -Content $json

    return @{ success = $true; message = "File Check '$Name' saved" }
} catch {
    return @{ success = $false; message = "Error saving file check: $($_.Exception.Message)"; statusCode = 500 }
}
