# Resolve a credential — returns decrypted values for script/API consumption
param(
    [Parameter(Mandatory)] [string]$Name
)

try {
    $content = Read-Blob -Container 'nexus-credentials' -BlobPath "$Name.json"
    if (-not $content) {
        return @{ success = $false; message = "Credential '$Name' not found"; statusCode = 404 }
    }

    $cred = $content | ConvertFrom-Json

    # Decrypt secret fields
    $resolved = @{}
    if ($cred.values) {
        foreach ($prop in $cred.values.PSObject.Properties) {
            if ($prop.Value -match '^ENC::') {
                $resolved[$prop.Name] = Unprotect-CredentialValue -Encrypted $prop.Value
            } else {
                $resolved[$prop.Name] = $prop.Value
            }
        }
    }

    return @{
        success = $true
        credential = @{
            name   = $cred.name
            type   = $cred.type
            values = $resolved
        }
    }
} catch {
    return @{ success = $false; message = "Error resolving credential: $($_.Exception.Message)"; statusCode = 500 }
}
