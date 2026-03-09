# Save a webhook configuration to nexus-webhooks container
param(
    [Parameter(Mandatory)] [string]$Name,
    [Parameter(Mandatory)] [string]$Uri,
    [string]$AuthType = 'none',
    [string]$TenantId = '',
    [string]$ClientId = '',
    [string]$ClientSecret = ''
)

if ([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($Uri)) {
    return @{ success = $false; message = "Name and URI are required"; statusCode = 400 }
}

try {
    $webhook = @{
        name         = $Name
        uri          = $Uri
        authType     = $AuthType
        tenantId     = $TenantId
        clientId     = $ClientId
        clientSecret = $ClientSecret
    }

    $json = $webhook | ConvertTo-Json -Depth 5
    Write-Blob -Container 'nexus-webhooks' -BlobPath "$Name.json" -Content $json

    return @{ success = $true; message = "Webhook '$Name' saved" }
} catch {
    return @{ success = $false; message = "Error saving webhook: $($_.Exception.Message)"; statusCode = 500 }
}
