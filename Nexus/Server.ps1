# Nexus - Automation Sequencer PODE Server

Import-Module Pode -Force -ErrorAction Stop
Import-Module Az.Storage -Force -ErrorAction SilentlyContinue
Import-Module Az.Accounts -Force -ErrorAction SilentlyContinue

Write-Host "Modules loaded successfully" -ForegroundColor Green

# Authenticate with Azure if service principal credentials are provided
if ($env:AZURE_CLIENT_ID -and $env:AZURE_CLIENT_SECRET -and $env:AZURE_TENANT_ID) {
    try {
        Write-Host "Authenticating with Azure using Service Principal..." -ForegroundColor Cyan
        $securePassword = ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($env:AZURE_CLIENT_ID, $securePassword)
        Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $env:AZURE_TENANT_ID -WarningAction SilentlyContinue | Out-Null
        Write-Host "Azure authentication successful!" -ForegroundColor Green
    }
    catch {
        Write-Host "Azure authentication failed: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "No Azure credentials provided. Storage operations will use account keys only." -ForegroundColor Yellow
}

Start-PodeServer -Threads 2 {
    Add-PodeEndpoint -Address 0.0.0.0 -Port 8080 -Protocol Http
    Enable-PodeSessionMiddleware -Duration 3600 -Extend
    Add-PodeStaticRoute -Path '/static' -Source './public'
    New-PodeLoggingMethod -Terminal | Enable-PodeErrorLogging

    # ===== BLOB STORAGE HELPERS =====
    # Container layout on configured storage account:
    #   nexus-config/        - workflow definitions, schedules, webhook configs
    #   nexus-powershell/    - uploaded PowerShell scripts
    #   nexus-terraform/     - uploaded Terraform plans
    #   nexus-python/        - uploaded Python scripts
    #   nexus-shell/         - uploaded Shell scripts
    #   nexus-webhooks/      - webhook JSON configs
    #   {workflow-name}/     - per-workflow container for logs and run data

    function Get-AppStorageContext {
        $cfg = Get-Content -Path './conf/config.json' -Raw | ConvertFrom-Json
        return New-AzStorageContext -StorageAccountName $cfg.storageAccount -StorageAccountKey $cfg.key
    }

    function Read-Blob {
        param([string]$Container, [string]$BlobPath)
        $ctx = Get-AppStorageContext
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            Get-AzStorageBlobContent -Container $Container -Blob $BlobPath -Destination $tempFile -Context $ctx -Force -ErrorAction Stop | Out-Null
            return Get-Content -Path $tempFile -Raw
        } catch {
            return $null
        } finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
        }
    }

    function Write-Blob {
        param([string]$Container, [string]$BlobPath, [string]$Content)
        $ctx = Get-AppStorageContext
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            [System.IO.File]::WriteAllText($tempFile, $Content, [System.Text.Encoding]::UTF8)
            Set-AzStorageBlobContent -Container $Container -Blob $BlobPath -File $tempFile -Context $ctx -Force | Out-Null
        } finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
        }
    }

    function Remove-Blob {
        param([string]$Container, [string]$BlobPath)
        $ctx = Get-AppStorageContext
        try {
            Remove-AzStorageBlob -Container $Container -Blob $BlobPath -Context $ctx -Force -ErrorAction Stop
        } catch { }
    }

    function Get-BlobList {
        param([string]$Container, [string]$Prefix)
        $ctx = Get-AppStorageContext
        try {
            if ($Prefix) {
                return Get-AzStorageBlob -Container $Container -Prefix $Prefix -Context $ctx -ErrorAction Stop
            } else {
                return Get-AzStorageBlob -Container $Container -Context $ctx -ErrorAction Stop
            }
        } catch {
            return @()
        }
    }

    # ===== STATIC ROUTE =====
    Add-PodeRoute -Method Get -Path '/' -ScriptBlock {
        Write-PodeFileResponse -Path './public/index.html' -ContentType 'text/html'
    }

    # Version endpoint
    Add-PodeRoute -Method Get -Path '/api/version' -ScriptBlock {
        try {
            $version = if (Test-Path './version.txt') {
                Get-Content -Path './version.txt' -Raw | ForEach-Object { $_.Trim() }
            } else {
                'dev'
            }
            Write-PodeJsonResponse -Value @{ version = $version }
        } catch {
            Write-PodeJsonResponse -Value @{ version = 'unknown' }
        }
    }

    # ===== CONFIGURATION ROUTES =====
    Add-PodeRoute -Method Get -Path '/api/config' -ScriptBlock {
        try {
            $configPath = './conf/config.json'
            if (Test-Path $configPath) {
                $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
                Write-PodeJsonResponse -Value @{
                    success        = $true
                    storageAccount = $config.storageAccount
                    key            = $config.key
                    resourceGroup  = $config.resourceGroup
                }
            } else {
                Write-PodeJsonResponse -Value @{
                    success        = $true
                    storageAccount = ''
                    key            = ''
                    resourceGroup  = ''
                }
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    Add-PodeRoute -Method Post -Path '/api/config' -ScriptBlock {
        $body = $WebEvent.Data
        try {
            $result = & './Scripts/PODE/SaveConfig.ps1' -StorageAccount $body.storageAccount -Key $body.key -ResourceGroup $body.resourceGroup
            if ($result.statusCode) {
                Write-PodeJsonResponse -Value $result -StatusCode $result.statusCode
            } else {
                Write-PodeJsonResponse -Value $result
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # Prepare storage containers
    Add-PodeRoute -Method Post -Path '/api/config/prepare' -ScriptBlock {
        try {
            $result = & './Scripts/PODE/PrepareContainers.ps1'
            if ($result.statusCode) {
                Write-PodeJsonResponse -Value $result -StatusCode $result.statusCode
            } else {
                Write-PodeJsonResponse -Value $result
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # ===== SCRIPT MANAGEMENT ROUTES =====

    # List scripts in a given type container
    Add-PodeRoute -Method Get -Path '/api/scripts/:type' -ScriptBlock {
        $scriptType = $WebEvent.Parameters['type']
        $container = "nexus-$scriptType"
        try {
            $result = & './Scripts/PODE/ListScripts.ps1' -Container $container
            Write-PodeJsonResponse -Value $result
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # Upload a script
    Add-PodeRoute -Method Post -Path '/api/scripts/:type' -ScriptBlock {
        $scriptType = $WebEvent.Parameters['type']
        $container = "nexus-$scriptType"
        try {
            # Pode stores files as a hashtable keyed by form field name
            $file = $WebEvent.Files['file']
            if (-not $file) {
                # Try grabbing first file from hashtable if key doesn't match
                $firstKey = $WebEvent.Files.Keys | Select-Object -First 1
                if ($firstKey) { $file = $WebEvent.Files[$firstKey] }
            }
            if (-not $file) {
                Write-PodeJsonResponse -Value @{ success = $false; message = "No file uploaded" } -StatusCode 400
                return
            }

            $fileName = $file.FileName
            # Save uploaded bytes to a temp file for blob upload
            $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) $fileName
            [System.IO.File]::WriteAllBytes($tempPath, $file.Bytes)

            try {
                $result = & './Scripts/PODE/UploadScript.ps1' -Container $container -FileName $fileName -FilePath $tempPath
                if ($result.statusCode) {
                    Write-PodeJsonResponse -Value $result -StatusCode $result.statusCode
                } else {
                    Write-PodeJsonResponse -Value $result
                }
            } finally {
                if (Test-Path $tempPath) { Remove-Item $tempPath -Force -ErrorAction SilentlyContinue }
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # Delete a script
    Add-PodeRoute -Method Delete -Path '/api/scripts/:type/:name' -ScriptBlock {
        $scriptType = $WebEvent.Parameters['type']
        $scriptName = $WebEvent.Parameters['name']
        $container = "nexus-$scriptType"
        try {
            Remove-Blob -Container $container -BlobPath $scriptName
            Write-PodeJsonResponse -Value @{ success = $true; message = "Script '$scriptName' deleted" }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # ===== WEBHOOK CONFIG ROUTES =====

    Add-PodeRoute -Method Get -Path '/api/webhooks' -ScriptBlock {
        try {
            $result = & './Scripts/PODE/ListWebhooks.ps1'
            Write-PodeJsonResponse -Value $result
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    Add-PodeRoute -Method Post -Path '/api/webhooks' -ScriptBlock {
        $body = $WebEvent.Data
        try {
            $result = & './Scripts/PODE/SaveWebhook.ps1' -Name $body.name -Uri $body.uri -AuthType $body.authType `
                -TenantId $body.tenantId -ClientId $body.clientId -ClientSecret $body.clientSecret
            if ($result.statusCode) {
                Write-PodeJsonResponse -Value $result -StatusCode $result.statusCode
            } else {
                Write-PodeJsonResponse -Value $result
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    Add-PodeRoute -Method Delete -Path '/api/webhooks/:name' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        try {
            Remove-Blob -Container 'nexus-webhooks' -BlobPath "$name.json"
            Write-PodeJsonResponse -Value @{ success = $true; message = "Webhook '$name' deleted" }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # ===== WORKFLOW ROUTES =====

    # List all workflows
    Add-PodeRoute -Method Get -Path '/api/workflows' -ScriptBlock {
        try {
            $result = & './Scripts/PODE/ListWorkflows.ps1'
            Write-PodeJsonResponse -Value $result
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # Get a single workflow
    Add-PodeRoute -Method Get -Path '/api/workflows/:name' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        try {
            $result = & './Scripts/PODE/GetWorkflow.ps1' -Name $name
            if ($result.statusCode) {
                Write-PodeJsonResponse -Value $result -StatusCode $result.statusCode
            } else {
                Write-PodeJsonResponse -Value $result
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # Save a workflow (create or update)
    Add-PodeRoute -Method Post -Path '/api/workflows' -ScriptBlock {
        $body = $WebEvent.Data
        try {
            $result = & './Scripts/PODE/SaveWorkflow.ps1' -WorkflowJson ($body | ConvertTo-Json -Depth 20)
            if ($result.statusCode) {
                Write-PodeJsonResponse -Value $result -StatusCode $result.statusCode
            } else {
                Write-PodeJsonResponse -Value $result
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # Delete a workflow
    Add-PodeRoute -Method Delete -Path '/api/workflows/:name' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        try {
            $result = & './Scripts/PODE/DeleteWorkflow.ps1' -Name $name
            if ($result.statusCode) {
                Write-PodeJsonResponse -Value $result -StatusCode $result.statusCode
            } else {
                Write-PodeJsonResponse -Value $result
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # ===== WORKFLOW EXECUTION ROUTES =====

    # Run a workflow manually
    Add-PodeRoute -Method Post -Path '/api/workflows/:name/run' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        try {
            $result = & './Scripts/PODE/RunWorkflow.ps1' -Name $name
            if ($result.statusCode) {
                Write-PodeJsonResponse -Value $result -StatusCode $result.statusCode
            } else {
                Write-PodeJsonResponse -Value $result
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # ===== SCHEDULE ROUTES =====

    Add-PodeRoute -Method Get -Path '/api/schedules' -ScriptBlock {
        try {
            $result = & './Scripts/PODE/ListSchedules.ps1'
            Write-PodeJsonResponse -Value $result
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    Add-PodeRoute -Method Post -Path '/api/schedules' -ScriptBlock {
        $body = $WebEvent.Data
        try {
            $result = & './Scripts/PODE/SaveSchedule.ps1' -ScheduleJson ($body | ConvertTo-Json -Depth 10)
            if ($result.statusCode) {
                Write-PodeJsonResponse -Value $result -StatusCode $result.statusCode
            } else {
                Write-PodeJsonResponse -Value $result
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    Add-PodeRoute -Method Delete -Path '/api/schedules/:name' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        try {
            Remove-Blob -Container 'nexus-config' -BlobPath "schedules/$name.json"
            Write-PodeJsonResponse -Value @{ success = $true; message = "Schedule '$name' deleted" }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # ===== LOGGING ROUTES =====

    # List workflow run logs
    Add-PodeRoute -Method Get -Path '/api/logs/:workflow' -ScriptBlock {
        $workflow = $WebEvent.Parameters['workflow']
        try {
            $result = & './Scripts/PODE/ListLogs.ps1' -Workflow $workflow
            Write-PodeJsonResponse -Value $result
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # Get a specific log file
    Add-PodeRoute -Method Get -Path '/api/logs/:workflow/:logName' -ScriptBlock {
        $workflow = $WebEvent.Parameters['workflow']
        $logName  = $WebEvent.Parameters['logName']
        try {
            $result = & './Scripts/PODE/GetLog.ps1' -Workflow $workflow -LogName $logName
            if ($result.statusCode) {
                Write-PodeJsonResponse -Value $result -StatusCode $result.statusCode
            } else {
                Write-PodeJsonResponse -Value $result
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # ===== PODE SCHEDULED TASKS (Timer) =====
    # Check every 60 seconds for due scheduled workflows
    Add-PodeTimer -Name 'ScheduleChecker' -Interval 60 -ScriptBlock {
        try {
            $configPath = './conf/config.json'
            if (-not (Test-Path $configPath)) { return }
            $cfg = Get-Content -Path $configPath -Raw | ConvertFrom-Json
            if ([string]::IsNullOrWhiteSpace($cfg.storageAccount)) { return }

            $ctx = New-AzStorageContext -StorageAccountName $cfg.storageAccount -StorageAccountKey $cfg.key
            $blobs = Get-AzStorageBlob -Container 'nexus-config' -Prefix 'schedules/' -Context $ctx -ErrorAction SilentlyContinue

            foreach ($blob in $blobs) {
                if ($blob.Name -notmatch '\.json$') { continue }
                $tempFile = [System.IO.Path]::GetTempFileName()
                try {
                    Get-AzStorageBlobContent -Container 'nexus-config' -Blob $blob.Name -Destination $tempFile -Context $ctx -Force | Out-Null
                    $schedule = Get-Content -Path $tempFile -Raw | ConvertFrom-Json

                    if ($schedule.enabled -ne $true) { continue }

                    $now = Get-Date
                    $nextRun = [DateTime]::Parse($schedule.nextRun)
                    if ($now -ge $nextRun) {
                        # Run the workflow
                        & './Scripts/PODE/RunWorkflow.ps1' -Name $schedule.workflow | Out-Null

                        # Advance nextRun based on interval
                        switch ($schedule.interval) {
                            "hourly"  { $nextRun = $nextRun.AddHours(1) }
                            "daily"   { $nextRun = $nextRun.AddDays(1) }
                            "weekly"  { $nextRun = $nextRun.AddDays(7) }
                            "monthly" { $nextRun = $nextRun.AddMonths(1) }
                        }
                        $schedule.nextRun = $nextRun.ToString('o')
                        $updatedJson = $schedule | ConvertTo-Json -Depth 10
                        [System.IO.File]::WriteAllText($tempFile, $updatedJson, [System.Text.Encoding]::UTF8)
                        Set-AzStorageBlobContent -Container 'nexus-config' -Blob $blob.Name -File $tempFile -Context $ctx -Force | Out-Null
                    }
                } catch {
                    Write-Host "Schedule check error for $($blob.Name): $($_.Exception.Message)" -ForegroundColor Red
                } finally {
                    if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
                }
            }
        } catch {
            Write-Host "Schedule timer error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
