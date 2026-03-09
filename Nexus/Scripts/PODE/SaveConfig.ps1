# Save application configuration to config.json
param(
    [Parameter(Mandatory)] [string]$StorageAccount,
    [Parameter(Mandatory)] [string]$Key,
    [Parameter(Mandatory)] [string]$ResourceGroup
)

$confDir = './conf'
if (-not (Test-Path $confDir)) {
    New-Item -Path $confDir -ItemType Directory -Force | Out-Null
}

$config = @{
    storageAccount = $StorageAccount
    key            = $Key
    resourceGroup  = $ResourceGroup
}

$config | ConvertTo-Json | Set-Content -Path './conf/config.json'

return @{
    success = $true
    message = "Configuration saved successfully"
}
