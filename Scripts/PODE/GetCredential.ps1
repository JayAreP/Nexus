# Get a single credential with secrets masked
param(
    [Parameter(Mandatory)] [string]$Name
)

try {
    $content = Read-Blob -Container 'nexus-credentials' -BlobPath "$Name.json"
    if (-not $content) {
        return @{ success = $false; message = "Credential '$Name' not found"; statusCode = 404 }
    }

    $cred = $content | ConvertFrom-Json

    # Mask secret values
    $maskedValues = @{}
    if ($cred.values) {
        foreach ($prop in $cred.values.PSObject.Properties) {
            if ($prop.Value -match '^ENC::') {
                $maskedValues[$prop.Name] = '********'
            } else {
                $maskedValues[$prop.Name] = $prop.Value
            }
        }
    }

    return @{
        success    = $true
        credential = @{
            name        = $cred.name
            type        = $cred.type
            description = $cred.description
            created     = $cred.created
            modified    = $cred.modified
            values      = $maskedValues
        }
    }
} catch {
    return @{ success = $false; message = "Error getting credential: $($_.Exception.Message)"; statusCode = 500 }
}
