# Save (create or update) a credential to nexus-credentials container
param(
    [Parameter(Mandatory)] [string]$CredentialJson,
    [Parameter(Mandatory)] [string]$CredentialTypesJson
)

try {
    $data = $CredentialJson | ConvertFrom-Json
    $credTypes = $CredentialTypesJson | ConvertFrom-Json

    if ([string]::IsNullOrWhiteSpace($data.name)) {
        return @{ success = $false; message = "Credential name is required"; statusCode = 400 }
    }
    if ([string]::IsNullOrWhiteSpace($data.type)) {
        return @{ success = $false; message = "Credential type is required"; statusCode = 400 }
    }

    # Validate name — only allow safe characters
    if ($data.name -notmatch '^[a-zA-Z0-9_-]+$') {
        return @{ success = $false; message = "Name may only contain letters, numbers, hyphens, and underscores"; statusCode = 400 }
    }

    # Look up the type definition to know which fields are secret
    $typeDef = $credTypes.($data.type)

    # Check if updating — preserve existing encrypted values if field sent as masked
    $existingValues = @{}
    $existingContent = Read-Blob -Container 'nexus-credentials' -BlobPath "$($data.name).json"
    if ($existingContent) {
        $existing = $existingContent | ConvertFrom-Json
        if ($existing.values) {
            foreach ($prop in $existing.values.PSObject.Properties) {
                $existingValues[$prop.Name] = $prop.Value
            }
        }
    }

    # Build values — encrypt secret fields
    $values = @{}
    if ($data.values) {
        foreach ($prop in $data.values.PSObject.Properties) {
            $fieldName = $prop.Name
            $fieldValue = $prop.Value

            # Determine if this field is secret
            $isSecret = $false
            if ($typeDef) {
                $fieldDef = $typeDef.fields | Where-Object { $_.name -eq $fieldName }
                if ($fieldDef -and $fieldDef.secret) { $isSecret = $true }
            }

            if ($isSecret) {
                # If value is the mask placeholder, keep existing encrypted value
                if ($fieldValue -eq '********' -and $existingValues.ContainsKey($fieldName)) {
                    $values[$fieldName] = $existingValues[$fieldName]
                } elseif (-not [string]::IsNullOrEmpty($fieldValue) -and $fieldValue -ne '********') {
                    $values[$fieldName] = Protect-CredentialValue -Plaintext $fieldValue
                }
            } else {
                $values[$fieldName] = $fieldValue
            }
        }
    }

    $now = (Get-Date).ToString('o')
    $credential = @{
        name        = $data.name
        type        = $data.type
        description = if ($data.description) { $data.description } else { '' }
        created     = if ($existingContent) { ($existingContent | ConvertFrom-Json).created } else { $now }
        modified    = $now
        values      = $values
    }

    $json = $credential | ConvertTo-Json -Depth 10
    Write-Blob -Container 'nexus-credentials' -BlobPath "$($data.name).json" -Content $json

    return @{ success = $true; message = "Credential '$($data.name)' saved" }
} catch {
    return @{ success = $false; message = "Error saving credential: $($_.Exception.Message)"; statusCode = 500 }
}
