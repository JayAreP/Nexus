# Prepare all required Azure Blob Storage containers for Nexus

$configPath = './conf/config.json'
if (-not (Test-Path $configPath)) {
    return @{ success = $false; message = "No configuration found. Save config first."; statusCode = 400 }
}

$cfg = Get-Content -Path $configPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($cfg.storageAccount)) {
    return @{ success = $false; message = "Storage account not configured"; statusCode = 400 }
}

try {
    $ctx = New-AzStorageContext -StorageAccountName $cfg.storageAccount -StorageAccountKey $cfg.key

    $containers = @(
        'nexus-config',
        'nexus-powershell',
        'nexus-terraform',
        'nexus-cloudformation',
        'nexus-armtemplate',
        'nexus-python',
        'nexus-shell',
        'nexus-webhooks',
        'nexus-credentials'
    )

    $created = @()
    foreach ($name in $containers) {
        $existing = Get-AzStorageContainer -Name $name -Context $ctx -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-AzStorageContainer -Name $name -Context $ctx -Permission Off | Out-Null
            $created += $name
        }
    }

    if ($created.Count -gt 0) {
        return @{ success = $true; message = "Created containers: $($created -join ', ')" }
    } else {
        return @{ success = $true; message = "All containers already exist" }
    }
} catch {
    return @{ success = $false; message = "Error preparing containers: $($_.Exception.Message)"; statusCode = 500 }
}
