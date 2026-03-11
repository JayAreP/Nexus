# Nexus - Automation Sequencer PODE Server

Import-Module Pode -Force -ErrorAction Stop
Import-Module Az.Storage -Force -ErrorAction SilentlyContinue
Import-Module Az.Accounts -Force -ErrorAction SilentlyContinue
Import-Module NLS -Force -ErrorAction SilentlyContinue

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

## ===== SANDBOX TERMINAL =====
# Start ttyd as a background process for the sandbox terminal
try {
    $ttydPath = '/usr/local/bin/ttyd'
    if (Test-Path $ttydPath) {
        $sandboxProc = Start-Process -FilePath $ttydPath -ArgumentList @(
            '-W',
            '-p', '7681',
            '-t', 'fontSize=14',
            '-t', 'theme={"background":"#1a202c","foreground":"#e2e8f0"}',
            'su', '-', 'sandbox'
        ) -PassThru -NoNewWindow
        Write-Host "Sandbox terminal started on port 7681 (PID: $($sandboxProc.Id))" -ForegroundColor Green
    } else {
        Write-Host "ttyd not found - sandbox terminal disabled" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Failed to start sandbox terminal: $($_.Exception.Message)" -ForegroundColor Red
}

Start-PodeServer -Threads 2 {
    Add-PodeEndpoint -Address 0.0.0.0 -Port 8080 -Protocol Http
    Enable-PodeSessionMiddleware -Duration 3600 -Extend
    Add-PodeStaticRoute -Path '/static' -Source './public'
    New-PodeLoggingMethod -Terminal | Enable-PodeErrorLogging

    # ===== BLOB STORAGE HELPERS =====
    # Container layout on configured storage account:
    #   nexus-config/        - workflow definitions, schedules, webhook configs, file check configs
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

    # ===== CREDENTIAL STORE HELPERS =====
    # Credential type definitions — each type defines its fields and which are secret
    $script:CredentialTypes = @{
        'usernamepassword' = @{
            label  = 'Username / Password'
            fields = @(
                @{ name = 'username'; label = 'Username'; type = 'text';     secret = $false }
                @{ name = 'password'; label = 'Password'; type = 'password'; secret = $true  }
            )
        }
        'azureserviceprincipal' = @{
            label  = 'Azure Service Principal'
            fields = @(
                @{ name = 'tenantId';     label = 'Tenant ID';     type = 'text';     secret = $false }
                @{ name = 'clientId';     label = 'Client ID';     type = 'text';     secret = $false }
                @{ name = 'clientSecret'; label = 'Client Secret'; type = 'password'; secret = $true  }
            )
        }
        'apikey' = @{
            label  = 'API Key'
            fields = @(
                @{ name = 'headerName'; label = 'Header Name'; type = 'text';     secret = $false }
                @{ name = 'key';        label = 'API Key';     type = 'password'; secret = $true  }
            )
        }
        'oauth2' = @{
            label  = 'OAuth2 Client Credentials'
            fields = @(
                @{ name = 'tokenUrl';     label = 'Token URL';     type = 'text';     secret = $false }
                @{ name = 'clientId';     label = 'Client ID';     type = 'text';     secret = $false }
                @{ name = 'clientSecret'; label = 'Client Secret'; type = 'password'; secret = $true  }
                @{ name = 'scope';        label = 'Scope';         type = 'text';     secret = $false }
            )
        }
        'aws' = @{
            label  = 'AWS Credentials'
            fields = @(
                @{ name = 'accessKeyId';     label = 'Access Key ID';     type = 'text';     secret = $false }
                @{ name = 'secretAccessKey'; label = 'Secret Access Key'; type = 'password'; secret = $true  }
                @{ name = 'region';          label = 'Region';            type = 'text';     secret = $false }
            )
        }
        'gcp' = @{
            label  = 'GCP Service Account'
            fields = @(
                @{ name = 'projectId';    label = 'Project ID';       type = 'text';     secret = $false }
                @{ name = 'clientEmail';  label = 'Client Email';     type = 'text';     secret = $false }
                @{ name = 'privateKey';   label = 'Private Key JSON'; type = 'textarea'; secret = $true  }
            )
        }
        'connectionstring' = @{
            label  = 'Connection String'
            fields = @(
                @{ name = 'connectionString'; label = 'Connection String'; type = 'password'; secret = $true }
            )
        }
        'token' = @{
            label  = 'Bearer Token'
            fields = @(
                @{ name = 'token'; label = 'Token'; type = 'password'; secret = $true }
            )
        }
    }

    function Protect-CredentialValue {
        param([string]$Plaintext)
        $keyBase64 = $env:NEXUS_CREDENTIAL_KEY
        if (-not $keyBase64) { throw 'NEXUS_CREDENTIAL_KEY environment variable is not set' }
        $key = [Convert]::FromBase64String($keyBase64)
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $key
        $aes.GenerateIV()
        $encryptor = $aes.CreateEncryptor()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Plaintext)
        $encrypted = $encryptor.TransformFinalBlock($bytes, 0, $bytes.Length)
        $payload = $aes.IV + $encrypted
        $aes.Dispose()
        return "ENC::$([Convert]::ToBase64String($payload))"
    }

    function Unprotect-CredentialValue {
        param([string]$Encrypted)
        $keyBase64 = $env:NEXUS_CREDENTIAL_KEY
        if (-not $keyBase64) { throw 'NEXUS_CREDENTIAL_KEY environment variable is not set' }
        $raw = $Encrypted -replace '^ENC::', ''
        $payload = [Convert]::FromBase64String($raw)
        $key = [Convert]::FromBase64String($keyBase64)
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $key
        $aes.IV = $payload[0..15]
        $decryptor = $aes.CreateDecryptor()
        $ciphertext = $payload[16..($payload.Length - 1)]
        $decrypted = $decryptor.TransformFinalBlock($ciphertext, 0, $ciphertext.Length)
        $aes.Dispose()
        return [System.Text.Encoding]::UTF8.GetString($decrypted)
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
            Write-PodeJsonResponse -Value @{ version = $version; serverTime = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
        } catch {
            Write-PodeJsonResponse -Value @{ version = 'unknown'; serverTime = '' }
        }
    }

    # ===== SANDBOX ROUTES =====
    Add-PodeRoute -Method Get -Path '/api/sandbox/status' -ScriptBlock {
        $ttydRunning = $false
        try {
            $proc = Get-Process -Name 'ttyd' -ErrorAction SilentlyContinue
            $ttydRunning = $null -ne $proc
        } catch { }
        Write-PodeJsonResponse -Value @{ success = $true; running = $ttydRunning; port = 7681 }
    }

    Add-PodeRoute -Method Post -Path '/api/sandbox/reset' -ScriptBlock {
        try {
            $workspacePath = '/home/sandbox/workspace'
            if (Test-Path $workspacePath) {
                Get-ChildItem -Path $workspacePath -Force | Remove-Item -Recurse -Force
            }
            Write-PodeJsonResponse -Value @{ success = $true; message = 'Sandbox workspace has been reset' }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = "Reset failed: $($_.Exception.Message)" }
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

    # Get script content (preview)
    Add-PodeRoute -Method Get -Path '/api/scripts/:type/:name/content' -ScriptBlock {
        $scriptType = $WebEvent.Parameters['type']
        $scriptName = $WebEvent.Parameters['name']
        $container = "nexus-$scriptType"
        try {
            $content = Read-Blob -Container $container -BlobPath $scriptName
            if (-not $content) {
                Write-PodeJsonResponse -Value @{ success = $false; message = "Script '$scriptName' not found" } -StatusCode 404
                return
            }
            Write-PodeJsonResponse -Value @{ success = $true; content = $content; name = $scriptName }
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

    # Get a single webhook config
    Add-PodeRoute -Method Get -Path '/api/webhooks/:name' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        try {
            $content = Read-Blob -Container 'nexus-webhooks' -BlobPath "$name.json"
            if (-not $content) {
                Write-PodeJsonResponse -Value @{ success = $false; message = "Webhook '$name' not found" } -StatusCode 404
                return
            }
            $wh = $content | ConvertFrom-Json
            Write-PodeJsonResponse -Value @{ success = $true; webhook = $wh }
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

    # ===== FILE CHECK CONFIG ROUTES =====

    Add-PodeRoute -Method Get -Path '/api/filechecks' -ScriptBlock {
        try {
            $result = & './Scripts/PODE/ListFileChecks.ps1'
            Write-PodeJsonResponse -Value $result
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    Add-PodeRoute -Method Post -Path '/api/filechecks' -ScriptBlock {
        $body = $WebEvent.Data
        try {
            $result = & './Scripts/PODE/SaveFileCheck.ps1' -Name $body.name -StorageAccount $body.storageAccount `
                -AuthType $body.authType -SasToken $body.sasToken
            if ($result.statusCode) {
                Write-PodeJsonResponse -Value $result -StatusCode $result.statusCode
            } else {
                Write-PodeJsonResponse -Value $result
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # Get a single file check config
    Add-PodeRoute -Method Get -Path '/api/filechecks/:name' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        try {
            $content = Read-Blob -Container 'nexus-config' -BlobPath "filechecks/$name.json"
            if (-not $content) {
                Write-PodeJsonResponse -Value @{ success = $false; message = "File Check '$name' not found" } -StatusCode 404
                return
            }
            $fc = $content | ConvertFrom-Json
            Write-PodeJsonResponse -Value @{ success = $true; filecheck = $fc }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    Add-PodeRoute -Method Delete -Path '/api/filechecks/:name' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        try {
            Remove-Blob -Container 'nexus-config' -BlobPath "filechecks/$name.json"
            Write-PodeJsonResponse -Value @{ success = $true; message = "File Check '$name' deleted" }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # ===== CREDENTIAL STORE ROUTES =====

    # Get credential type definitions (for dynamic form rendering)
    Add-PodeRoute -Method Get -Path '/api/credentials/types' -ScriptBlock {
        Write-PodeJsonResponse -Value @{ success = $true; types = $using:CredentialTypes }
    }

    # List all credentials (metadata only, no secrets)
    Add-PodeRoute -Method Get -Path '/api/credentials' -ScriptBlock {
        try {
            $result = & './Scripts/PODE/ListCredentials.ps1'
            Write-PodeJsonResponse -Value $result
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # Get a single credential (secrets masked)
    Add-PodeRoute -Method Get -Path '/api/credentials/:name' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        try {
            $result = & './Scripts/PODE/GetCredential.ps1' -Name $name
            if ($result.statusCode) {
                Write-PodeJsonResponse -Value $result -StatusCode $result.statusCode
            } else {
                Write-PodeJsonResponse -Value $result
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # Save a credential (create or update)
    Add-PodeRoute -Method Post -Path '/api/credentials' -ScriptBlock {
        $body = $WebEvent.Data
        try {
            $result = & './Scripts/PODE/SaveCredential.ps1' -CredentialJson ($body | ConvertTo-Json -Depth 10) -CredentialTypesJson ($using:CredentialTypes | ConvertTo-Json -Depth 10)
            if ($result.statusCode) {
                Write-PodeJsonResponse -Value $result -StatusCode $result.statusCode
            } else {
                Write-PodeJsonResponse -Value $result
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # Delete a credential
    Add-PodeRoute -Method Delete -Path '/api/credentials/:name' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        try {
            Remove-Blob -Container 'nexus-credentials' -BlobPath "$name.json"
            Write-PodeJsonResponse -Value @{ success = $true; message = "Credential '$name' deleted" }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # Resolve credential — returns decrypted values (for script/API consumption)
    Add-PodeRoute -Method Get -Path '/api/credentials/:name/resolve' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        try {
            $result = & './Scripts/PODE/ResolveCredential.ps1' -Name $name
            if ($result.statusCode) {
                Write-PodeJsonResponse -Value $result -StatusCode $result.statusCode
            } else {
                Write-PodeJsonResponse -Value $result
            }
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

    # Export a workflow (with optional webhooks/filechecks)
    Add-PodeRoute -Method Get -Path '/api/workflows/:name/export' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        $includeWebhooks = $WebEvent.Query['webhooks'] -eq 'true'
        $includeFilechecks = $WebEvent.Query['filechecks'] -eq 'true'
        try {
            $wfContent = Read-Blob -Container 'nexus-config' -BlobPath "workflows/$name.json"
            if (-not $wfContent) {
                Write-PodeJsonResponse -Value @{ success = $false; message = "Workflow '$name' not found" } -StatusCode 404
                return
            }
            $workflow = $wfContent | ConvertFrom-Json

            $webhooks = @()
            $filechecks = @()

            if ($includeWebhooks -or $includeFilechecks) {
                foreach ($step in $workflow.steps) {
                    if ($includeWebhooks -and $step.type -eq 'webhook' -and $step.webhook) {
                        $whContent = Read-Blob -Container 'nexus-webhooks' -BlobPath "$($step.webhook).json"
                        if ($whContent) {
                            $wh = $whContent | ConvertFrom-Json
                            # Avoid duplicates
                            if (-not ($webhooks | Where-Object { $_.name -eq $wh.name })) {
                                $webhooks += $wh
                            }
                        }
                    }
                    if ($includeFilechecks -and $step.type -eq 'filecheck' -and $step.filecheck) {
                        $fcContent = Read-Blob -Container 'nexus-config' -BlobPath "filechecks/$($step.filecheck).json"
                        if ($fcContent) {
                            $fc = $fcContent | ConvertFrom-Json
                            if (-not ($filechecks | Where-Object { $_.name -eq $fc.name })) {
                                $filechecks += $fc
                            }
                        }
                    }
                }
            }

            $export = @{
                workflow   = $workflow
                webhooks   = $webhooks
                filechecks = $filechecks
            }

            Write-PodeJsonResponse -Value @{ success = $true; export = $export }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # Import a workflow (with optional webhooks/filechecks)
    Add-PodeRoute -Method Post -Path '/api/workflows/import' -ScriptBlock {
        $body = $WebEvent.Data
        $importWebhooks = [bool]$body.importWebhooks
        $importFilechecks = [bool]$body.importFilechecks
        $payload = $body.payload

        try {
            if (-not $payload -or -not $payload.workflow) {
                Write-PodeJsonResponse -Value @{ success = $false; message = 'Invalid import file: missing workflow data' } -StatusCode 400
                return
            }

            $workflow = $payload.workflow

            # Validate that referenced scripts exist
            $missingScripts = @()
            foreach ($step in $workflow.steps) {
                if ($step.type -notin @('webhook', 'filecheck') -and $step.script) {
                    $container = "nexus-$($step.type)"
                    $content = Read-Blob -Container $container -BlobPath $step.script
                    if (-not $content) {
                        $missingScripts += "$($step.script) ($($step.type))"
                    }
                }
            }

            if ($missingScripts.Count -gt 0) {
                $list = $missingScripts -join ', '
                Write-PodeJsonResponse -Value @{
                    success = $false
                    message = "The following scripts are missing and must be uploaded first: $list"
                    missingScripts = $missingScripts
                } -StatusCode 400
                return
            }

            # Import webhooks if requested
            if ($importWebhooks -and $payload.webhooks) {
                foreach ($wh in $payload.webhooks) {
                    if ($wh.name) {
                        $whJson = $wh | ConvertTo-Json -Depth 10
                        Write-Blob -Container 'nexus-webhooks' -BlobPath "$($wh.name).json" -Content $whJson
                    }
                }
            }

            # Import filechecks if requested
            if ($importFilechecks -and $payload.filechecks) {
                foreach ($fc in $payload.filechecks) {
                    if ($fc.name) {
                        $fcJson = $fc | ConvertTo-Json -Depth 10
                        Write-Blob -Container 'nexus-config' -BlobPath "filechecks/$($fc.name).json" -Content $fcJson
                    }
                }
            }

            # Save workflow
            $wfJson = $workflow | ConvertTo-Json -Depth 20
            $result = & './Scripts/PODE/SaveWorkflow.ps1' -WorkflowJson $wfJson

            if ($result.success) {
                Write-PodeJsonResponse -Value @{ success = $true; message = "Workflow '$($workflow.name)' imported successfully" }
            } else {
                if ($result.statusCode) {
                    Write-PodeJsonResponse -Value $result -StatusCode $result.statusCode
                } else {
                    Write-PodeJsonResponse -Value $result
                }
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = "Import failed: $($_.Exception.Message)" } -StatusCode 500
        }
    }

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

    # Live console output (polls temp file written by RunWorkflow)
    Add-PodeRoute -Method Get -Path '/api/workflows/:name/console' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "nexus-console-$($name.ToLower()).log"
        if (Test-Path $tempFile) {
            $content = [System.IO.File]::ReadAllText($tempFile, [System.Text.Encoding]::UTF8)
            Write-PodeJsonResponse -Value @{ running = $true; output = $content }
        } else {
            Write-PodeJsonResponse -Value @{ running = $false; output = '' }
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

    # ===== MODULE MANAGEMENT ROUTES =====

    # List installed modules
    Add-PodeRoute -Method Get -Path '/api/modules/:type' -ScriptBlock {
        $type = $WebEvent.Parameters['type']
        try {
            if ($type -eq 'powershell') {
                $modules = Get-Module -ListAvailable | Select-Object Name, @{N='Version';E={$_.Version.ToString()}}, Path | Sort-Object Name
                $result = @()
                foreach ($m in $modules) {
                    $result += @{ name = $m.Name; version = $m.Version; path = $m.Path }
                }
                Write-PodeJsonResponse -Value @{ success = $true; modules = $result }
            } elseif ($type -eq 'python') {
                $output = & pip3 list 2>&1 | Out-String
                Write-PodeJsonResponse -Value @{ success = $true; output = $output }
            } else {
                Write-PodeJsonResponse -Value @{ success = $false; message = "Unknown module type: $type" } -StatusCode 400
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # Install a module
    Add-PodeRoute -Method Post -Path '/api/modules/:type' -ScriptBlock {
        $type = $WebEvent.Parameters['type']
        $body = $WebEvent.Data
        $moduleName = $body.name
        if ([string]::IsNullOrWhiteSpace($moduleName)) {
            Write-PodeJsonResponse -Value @{ success = $false; message = 'Module name is required' } -StatusCode 400
            return
        }
        # Validate module name - only allow alphanumeric, dots, hyphens, underscores
        if ($moduleName -notmatch '^[a-zA-Z0-9._-]+$') {
            Write-PodeJsonResponse -Value @{ success = $false; message = 'Invalid module name. Only letters, numbers, dots, hyphens, and underscores are allowed.' } -StatusCode 400
            return
        }
        try {
            if ($type -eq 'powershell') {
                $output = Install-Module -Name $moduleName -Scope AllUsers -Force -AllowClobber -ErrorAction Stop 2>&1 | Out-String
                Write-PodeJsonResponse -Value @{ success = $true; message = "PowerShell module '$moduleName' installed successfully" }
            } elseif ($type -eq 'python') {
                $output = & pip3 install $moduleName 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) {
                    Write-PodeJsonResponse -Value @{ success = $false; message = "pip3 install failed: $output" } -StatusCode 500
                } else {
                    Write-PodeJsonResponse -Value @{ success = $true; message = "Python module '$moduleName' installed successfully" }
                }
            } else {
                Write-PodeJsonResponse -Value @{ success = $false; message = "Unknown module type: $type" } -StatusCode 400
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = "Install failed: $($_.Exception.Message)" } -StatusCode 500
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
