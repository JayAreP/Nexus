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
# Start ttyd as a background process for the sandbox terminal (localhost only, behind nginx)
try {
    $ttydPath = '/usr/local/bin/ttyd'
    if (Test-Path $ttydPath) {
        $sandboxProc = Start-Process -FilePath $ttydPath -ArgumentList @(
            '-W',
            '-i', '127.0.0.1',
            '-p', '7681',
            '-b', '/terminal',
            '-t', 'fontSize=14',
            '-t', 'theme={"background":"#1a202c","foreground":"#e2e8f0"}',
            'su', '-', 'sandbox'
        ) -PassThru -NoNewWindow
        Write-Host "Sandbox terminal started on 127.0.0.1:7681 /terminal (PID: $($sandboxProc.Id))" -ForegroundColor Green
    } else {
        Write-Host "ttyd not found - sandbox terminal disabled" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Failed to start sandbox terminal: $($_.Exception.Message)" -ForegroundColor Red
}

## ===== NGINX REVERSE PROXY =====
# Start nginx as the single-port front door (port 8080 → PODE 8081 + ttyd 7681)
try {
    Start-Process -FilePath 'nginx' -NoNewWindow
    Write-Host "nginx reverse proxy started on port 8080" -ForegroundColor Green
} catch {
    Write-Host "Failed to start nginx: $($_.Exception.Message)" -ForegroundColor Red
}

Start-PodeServer -Threads 4 {
    Add-PodeEndpoint -Address 0.0.0.0 -Port 8081 -Protocol Http
    Enable-PodeSessionMiddleware -Duration 3600 -Extend
    Add-PodeStaticRoute -Path '/static' -Source './public'
    New-PodeLoggingMethod -Terminal | Enable-PodeErrorLogging

    # Thread-safe lock to prevent concurrent runs of the same workflow
    $lockTable = [System.Collections.Concurrent.ConcurrentDictionary[string, byte]]::new()
    Set-PodeState -Name 'RunningWorkflows' -Value $lockTable | Out-Null

    # Store for async workflow results
    $resultTable = [System.Collections.Concurrent.ConcurrentDictionary[string, hashtable]]::new()
    Set-PodeState -Name 'WorkflowResults' -Value $resultTable | Out-Null

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

    # ===== ENGINE LOG =====
    # Thread-safe append-only log with daily rotation (nexus-engine-YYYY-MM-DD.log)
    $engineLogDir = [System.IO.Path]::GetTempPath()
    Set-PodeState -Name 'EngineLogDir' -Value $engineLogDir | Out-Null

    function Get-EngineLogFile {
        $dir = Get-PodeState -Name 'EngineLogDir'
        if (-not $dir) { $dir = [System.IO.Path]::GetTempPath() }
        return Join-Path $dir "nexus-engine-$(Get-Date -Format 'yyyy-MM-dd').log"
    }

    function Write-EngineLog {
        param([string]$Message, [string]$Level = 'INFO')
        $logFile = Get-EngineLogFile
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message`n"
        try { [System.IO.File]::AppendAllText($logFile, $line, [System.Text.Encoding]::UTF8) } catch { }
    }

    Write-EngineLog "Nexus server started" "ENGINE"

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
                @{ name = 'sessionToken';    label = 'Session Token';     type = 'password'; secret = $true  }
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
        Write-PodeJsonResponse -Value @{ success = $true; running = $ttydRunning; path = '/terminal/' }
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

    # Update script content (from editor)
    Add-PodeRoute -Method Put -Path '/api/scripts/:type/:name' -ScriptBlock {
        $scriptType = $WebEvent.Parameters['type']
        $scriptName = $WebEvent.Parameters['name']
        $container = "nexus-$scriptType"
        try {
            $body = $WebEvent.Data
            if (-not $body.content) {
                Write-PodeJsonResponse -Value @{ success = $false; message = 'No content provided' } -StatusCode 400
                return
            }
            Write-Blob -Container $container -BlobPath $scriptName -Content $body.content
            Write-PodeJsonResponse -Value @{ success = $true; message = "Script '$scriptName' saved" }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # Auto-detect script parameters by parsing the script source
    Add-PodeRoute -Method Get -Path '/api/scripts/:type/:name/parameters' -ScriptBlock {
        $scriptType = $WebEvent.Parameters['type']
        $scriptName = $WebEvent.Parameters['name']
        $container = "nexus-$scriptType"
        try {
            $content = Read-Blob -Container $container -BlobPath $scriptName
            if (-not $content) {
                Write-PodeJsonResponse -Value @{ success = $false; message = "Script '$scriptName' not found" } -StatusCode 404
                return
            }
            $result = & './Scripts/PODE/Get-ScriptParameters.ps1' -Type $scriptType -Content $content
            Write-PodeJsonResponse -Value $result
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

    # Browse containers on a file check's storage account
    Add-PodeRoute -Method Get -Path '/api/filechecks/:name/containers' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        try {
            $content = Read-Blob -Container 'nexus-config' -BlobPath "filechecks/$name.json"
            if (-not $content) {
                Write-PodeJsonResponse -Value @{ success = $false; message = "File Check '$name' not found" } -StatusCode 404
                return
            }
            $fc = $content | ConvertFrom-Json
            $fcCtx = if ($fc.authType -eq 'sas') {
                New-AzStorageContext -StorageAccountName $fc.storageAccount -SasToken $fc.sasToken
            } else {
                New-AzStorageContext -StorageAccountName $fc.storageAccount -UseConnectedAccount
            }
            $containers = Get-AzStorageContainer -Context $fcCtx -ErrorAction Stop |
                ForEach-Object { @{ name = $_.Name } }
            Write-PodeJsonResponse -Value @{ success = $true; containers = @($containers) }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = $_.Exception.Message } -StatusCode 500
        }
    }

    # Browse blobs/folders within a container on a file check's storage account
    Add-PodeRoute -Method Get -Path '/api/filechecks/:name/browse' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        $container = $WebEvent.Query['container']
        $prefix = $WebEvent.Query['prefix']
        if ([string]::IsNullOrWhiteSpace($container)) {
            Write-PodeJsonResponse -Value @{ success = $false; message = 'container parameter required' } -StatusCode 400
            return
        }
        try {
            $content = Read-Blob -Container 'nexus-config' -BlobPath "filechecks/$name.json"
            if (-not $content) {
                Write-PodeJsonResponse -Value @{ success = $false; message = "File Check '$name' not found" } -StatusCode 404
                return
            }
            $fc = $content | ConvertFrom-Json
            $fcCtx = if ($fc.authType -eq 'sas') {
                New-AzStorageContext -StorageAccountName $fc.storageAccount -SasToken $fc.sasToken
            } else {
                New-AzStorageContext -StorageAccountName $fc.storageAccount -UseConnectedAccount
            }
            # Use delimiter to get virtual directories
            $params = @{
                Container = $container
                Context   = $fcCtx
                ErrorAction = 'Stop'
            }
            if (![string]::IsNullOrWhiteSpace($prefix)) {
                $params.Prefix = $prefix
            }
            $blobs = Get-AzStorageBlob @params

            # Extract virtual folders (prefixes) and files at this level
            $folders = @{}
            $files = @()
            $prefixLen = if ($prefix) { $prefix.Length } else { 0 }

            foreach ($b in $blobs) {
                $relative = $b.Name.Substring($prefixLen)
                $slashIdx = $relative.IndexOf('/')
                if ($slashIdx -ge 0) {
                    $folderName = $relative.Substring(0, $slashIdx)
                    $fullPrefix = if ($prefix) { "$prefix$folderName/" } else { "$folderName/" }
                    $folders[$folderName] = $fullPrefix
                } else {
                    $files += @{ name = $relative; fullPath = $b.Name; size = $b.Length }
                }
            }

            $folderList = $folders.GetEnumerator() | Sort-Object Key | ForEach-Object {
                @{ name = $_.Key; prefix = $_.Value }
            }

            Write-PodeJsonResponse -Value @{
                success = $true
                folders = @($folderList)
                files   = @($files)
                prefix  = ($prefix ?? '')
            }
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

    # Run a workflow manually — fires async and returns immediately
    Add-PodeRoute -Method Post -Path '/api/workflows/:name/run' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        $running = Get-PodeState -Name 'RunningWorkflows'
        if (-not $running.TryAdd($name, [byte]0)) {
            Write-EngineLog "RUN BLOCKED: '$name' — already running" 'WARN'
            Write-PodeJsonResponse -Value @{ success = $false; message = "Workflow '$name' is already running" } -StatusCode 409
            return
        }
        Write-EngineLog "RUN REQUEST: '$name' — accepted, firing timer"
        $results = Get-PodeState -Name 'WorkflowResults'
        $results[$name] = @{ status = 'running'; message = '' }
        # Fire a one-shot timer — runs in Pode's timer runspace with full server function access
        $timerName = "wf-run-$name-$((Get-Date).Ticks)"
        Add-PodeTimer -Name $timerName -Interval 1 -Limit 1 -ArgumentList @($name) -ScriptBlock {
            param($wfName)
            Write-EngineLog "TIMER FIRED: '$wfName' — starting execution"
            $running = Get-PodeState -Name 'RunningWorkflows'
            $results = Get-PodeState -Name 'WorkflowResults'
            try {
                $result = & './Scripts/PODE/RunWorkflow.ps1' -Name $wfName
                $status = if ($result.success) { 'success' } else { 'failed' }
                $results[$wfName] = @{ status = $status; message = $result.message }
                Write-EngineLog "RUN COMPLETE: '$wfName' — $status — $($result.message)"
            } catch {
                $results[$wfName] = @{ status = 'failed'; message = $_.Exception.Message }
                Write-EngineLog "RUN EXCEPTION: '$wfName' — $($_.Exception.Message)" 'ERROR'
            } finally {
                [void]$running.TryRemove($wfName, [ref][byte]0)
                Write-EngineLog "LOCK RELEASED: '$wfName'"
            }
        }
        Write-PodeJsonResponse -Value @{ success = $true; message = "Workflow '$name' started" }
    }

    # Run a single step (test mode) — fires async and returns immediately
    Add-PodeRoute -Method Post -Path '/api/workflows/:name/run-step' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        $stepIndex = [int]$WebEvent.Data.stepIndex
        $running = Get-PodeState -Name 'RunningWorkflows'
        if (-not $running.TryAdd($name, [byte]0)) {
            Write-EngineLog "RUN-STEP BLOCKED: '$name' — already running" 'WARN'
            Write-PodeJsonResponse -Value @{ success = $false; message = "Workflow '$name' is already running" } -StatusCode 409
            return
        }
        Write-EngineLog "RUN-STEP REQUEST: '$name' step $($stepIndex + 1) — accepted, firing timer"
        $results = Get-PodeState -Name 'WorkflowResults'
        $results[$name] = @{ status = 'running'; message = '' }
        $timerName = "wf-step-$name-$stepIndex-$((Get-Date).Ticks)"
        Add-PodeTimer -Name $timerName -Interval 1 -Limit 1 -ArgumentList @($name, $stepIndex) -ScriptBlock {
            param($wfName, $si)
            Write-EngineLog "TIMER FIRED: '$wfName' step $($si + 1) — starting execution"
            $running = Get-PodeState -Name 'RunningWorkflows'
            $results = Get-PodeState -Name 'WorkflowResults'
            try {
                $result = & './Scripts/PODE/RunWorkflow.ps1' -Name $wfName -StepIndex $si
                $status = if ($result.success) { 'success' } else { 'failed' }
                $results[$wfName] = @{ status = $status; message = $result.message }
                Write-EngineLog "RUN-STEP COMPLETE: '$wfName' step $($si + 1) — $status — $($result.message)"
            } catch {
                $results[$wfName] = @{ status = 'failed'; message = $_.Exception.Message }
                Write-EngineLog "RUN-STEP EXCEPTION: '$wfName' step $($si + 1) — $($_.Exception.Message)" 'ERROR'
            } finally {
                [void]$running.TryRemove($wfName, [ref][byte]0)
                Write-EngineLog "LOCK RELEASED: '$wfName'"
            }
        }
        Write-PodeJsonResponse -Value @{ success = $true; message = "Test step $($stepIndex + 1) of '$name' started" }
    }

    # Live console output (polls temp file written by RunWorkflow)
    Add-PodeRoute -Method Get -Path '/api/workflows/:name/console' -ScriptBlock {
        $name = $WebEvent.Parameters['name']
        $running = Get-PodeState -Name 'RunningWorkflows'
        $results = Get-PodeState -Name 'WorkflowResults'
        $isRunning = $running.ContainsKey($name)
        $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "nexus-console-$($name.ToLower()).log"
        $output = ''
        if (Test-Path $tempFile) {
            $output = [System.IO.File]::ReadAllText($tempFile, [System.Text.Encoding]::UTF8)
        }
        $result = @{ running = $isRunning; output = $output }
        if (-not $isRunning -and $results.ContainsKey($name)) {
            $result.status = $results[$name].status
            $result.message = $results[$name].message
        }
        Write-PodeJsonResponse -Value $result
    }

    # Engine log viewer — returns last N lines
    # List available engine log files
    Add-PodeRoute -Method Get -Path '/api/engine-logs' -ScriptBlock {
        $dir = Get-PodeState -Name 'EngineLogDir'
        if (-not $dir) { $dir = [System.IO.Path]::GetTempPath() }
        $files = Get-ChildItem -Path $dir -Filter 'nexus-engine-*.log' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object {
                $datePart = $_.BaseName -replace '^nexus-engine-', ''
                @{ date = $datePart; size = $_.Length }
            }
        Write-PodeJsonResponse -Value @{ success = $true; logs = @($files) }
    }

    # Read a specific engine log by date (defaults to today)
    Add-PodeRoute -Method Get -Path '/api/engine-log' -ScriptBlock {
        $date = $WebEvent.Query['date']
        if (-not $date) { $date = Get-Date -Format 'yyyy-MM-dd' }
        # Sanitize: only allow YYYY-MM-DD format
        if ($date -notmatch '^\d{4}-\d{2}-\d{2}$') {
            Write-PodeJsonResponse -Value @{ success = $false; message = 'Invalid date format' } -StatusCode 400
            return
        }
        $dir = Get-PodeState -Name 'EngineLogDir'
        if (-not $dir) { $dir = [System.IO.Path]::GetTempPath() }
        $logFile = Join-Path $dir "nexus-engine-$date.log"
        if (Test-Path $logFile) {
            $content = Get-Content -Path $logFile -Raw -ErrorAction SilentlyContinue
            Write-PodeJsonResponse -Value @{ success = $true; log = ($content ?? '') }
        } else {
            Write-PodeJsonResponse -Value @{ success = $true; log = "(no log for $date)" }
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
            } elseif ($type -eq 'apt') {
                # Packages bundled in the container image
                $defaults = @(
                    @{ name='python3';          source='apt';    note='Python 3 runtime' }
                    @{ name='python3-pip';      source='apt';    note='Python package manager' }
                    @{ name='git';              source='apt';    note='Version control' }
                    @{ name='curl';             source='apt';    note='HTTP client' }
                    @{ name='unzip';            source='apt';    note='Archive extraction' }
                    @{ name='gnupg';            source='apt';    note='GPG key management' }
                    @{ name='azure-cli';        source='apt';    note='Azure CLI (az)' }
                    @{ name='google-cloud-cli'; source='apt';    note='Google Cloud CLI (gcloud)' }
                    @{ name='aws-cli-v2';       source='manual'; note='AWS CLI v2 (aws)' }
                    @{ name='terraform';        source='manual'; note='Terraform IaC tool' }
                )
                # Merge with user-installed packages from file
                $pkgFile = '/app/conf/apt-packages.json'
                $userPkgs = if (Test-Path $pkgFile) { @(Get-Content $pkgFile -Raw | ConvertFrom-Json) } else { @() }
                $defaultNames = $defaults | ForEach-Object { $_.name }
                $allPackages = $defaults + @($userPkgs | Where-Object { $_.name -notin $defaultNames })
                $result = @()
                foreach ($pkg in $allPackages) {
                    $ver = if ($pkg.version) { $pkg.version } else { '' }
                    if ($pkg.source -eq 'apt') {
                        $verOut = & dpkg-query -W --showformat='${Version}' $pkg.name 2>&1
                        $ver = if ($LASTEXITCODE -eq 0) { ($verOut -join '').Trim() } else { 'not installed' }
                    } elseif ($pkg.name -eq 'aws-cli-v2') {
                        $verOut = (& aws --version 2>&1) -join ''
                        $ver = if ($LASTEXITCODE -eq 0) { $verOut.Trim() } else { 'not installed' }
                    } elseif ($pkg.name -eq 'terraform') {
                        $verOut = (& terraform version 2>&1 | Select-Object -First 1) -join ''
                        $ver = if ($LASTEXITCODE -eq 0) { $verOut.Trim() } else { 'not installed' }
                    }
                    $isInstalled = $ver -ne 'not installed'
                    $result += @{ name = $pkg.name; version = $ver; note = $pkg.note; source = $pkg.source; installed = $isInstalled }
                }
                Write-PodeJsonResponse -Value @{ success = $true; packages = $result }
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
            } elseif ($type -eq 'apt') {
                if ($moduleName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._+:-]*$') {
                    Write-PodeJsonResponse -Value @{ success = $false; message = 'Invalid package name' } -StatusCode 400
                    return
                }
                $env:DEBIAN_FRONTEND = 'noninteractive'
                & apt-get update 2>&1 | Out-Null
                $output = & apt-get install -y $moduleName 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) {
                    Write-PodeJsonResponse -Value @{ success = $false; message = "apt-get install failed: $output" } -StatusCode 500
                    return
                }
                $ver = (& dpkg-query -W --showformat='${Version}' $moduleName 2>&1) -join ''
                $pkgFile = '/app/conf/apt-packages.json'
                $packages = if (Test-Path $pkgFile) { @(Get-Content $pkgFile -Raw | ConvertFrom-Json) } else { @() }
                if (-not ($packages | Where-Object { $_.name -eq $moduleName })) {
                    $packages += @{ name = $moduleName; version = $ver.Trim(); source = 'apt'; note = '' }
                    $packages | ConvertTo-Json -Depth 5 | Set-Content $pkgFile
                }
                Write-PodeJsonResponse -Value @{ success = $true; message = "Package '$moduleName' installed ($($ver.Trim()))" }
            } else {
                Write-PodeJsonResponse -Value @{ success = $false; message = "Unknown module type: $type" } -StatusCode 400
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = "Install failed: $($_.Exception.Message)" } -StatusCode 500
        }
    }

    # Remove a PowerShell module
    Add-PodeRoute -Method Delete -Path '/api/modules/:name' -ScriptBlock {
        $moduleName = $WebEvent.Parameters['name']
        if ([string]::IsNullOrWhiteSpace($moduleName) -or $moduleName -notmatch '^[a-zA-Z0-9._-]+$') {
            Write-PodeJsonResponse -Value @{ success = $false; message = 'Invalid module name' } -StatusCode 400
            return
        }
        try {
            # Unload from memory if loaded
            Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue

            # Remove all versions from all module paths
            $removed = $false
            $env:PSModulePath -split ':' | ForEach-Object {
                $modulePath = Join-Path $_ $moduleName
                if (Test-Path $modulePath) {
                    Remove-Item -Path $modulePath -Recurse -Force
                    $removed = $true
                }
            }
            if ($removed) {
                Write-PodeJsonResponse -Value @{ success = $true; message = "Module '$moduleName' removed" }
            } else {
                Write-PodeJsonResponse -Value @{ success = $false; message = "Module '$moduleName' not found on disk" } -StatusCode 404
            }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = "Remove failed: $($_.Exception.Message)" } -StatusCode 500
        }
    }

    # Install a PowerShell module from GitHub
    Add-PodeRoute -Method Post -Path '/api/modules/github' -ScriptBlock {
        $body = $WebEvent.Data
        $gitUrl = $body.url
        if ([string]::IsNullOrWhiteSpace($gitUrl)) {
            Write-PodeJsonResponse -Value @{ success = $false; message = 'GitHub URL is required' } -StatusCode 400
            return
        }
        # Validate URL is a GitHub repo
        if ($gitUrl -notmatch '^https://github\.com/[\w.-]+/[\w.-]+(/?)$') {
            Write-PodeJsonResponse -Value @{ success = $false; message = 'URL must be a GitHub repository (https://github.com/owner/repo)' } -StatusCode 400
            return
        }
        $gitUrl = $gitUrl.TrimEnd('/')
        if (-not $gitUrl.EndsWith('.git')) { $gitUrl += '.git' }

        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "nexus-gh-$(Get-Random)"
        try {
            # Clone the repo
            $cloneOutput = & git clone --depth 1 $gitUrl $tempDir 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                throw "git clone failed: $cloneOutput"
            }

            # Find the .psd1 manifest
            $psd1Files = Get-ChildItem -Path $tempDir -Filter '*.psd1' -Recurse | Where-Object { $_.Name -ne 'PSScriptAnalyzerSettings.psd1' }
            if ($psd1Files.Count -eq 0) {
                throw 'No PowerShell module manifest (.psd1) found in repository'
            }

            $psd1File = $psd1Files | Select-Object -First 1
            $manifest = Import-PowerShellDataFile -Path $psd1File.FullName
            $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($psd1File.Name)
            $moduleVersion = if ($manifest.ModuleVersion) { $manifest.ModuleVersion } else { '1.0.0' }

            # Determine source directory (the folder containing the .psd1)
            $sourceDir = $psd1File.DirectoryName

            # Install to system-wide PS modules path
            $targetDir = "/usr/local/share/powershell/Modules/$moduleName/$moduleVersion"
            if (Test-Path $targetDir) {
                Remove-Item -Path $targetDir -Recurse -Force
            }
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

            # Copy module files (from the manifest's directory)
            Get-ChildItem -Path $sourceDir -Recurse | ForEach-Object {
                $relativePath = $_.FullName.Substring($sourceDir.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
                $destPath = Join-Path $targetDir $relativePath
                if ($_.PSIsContainer) {
                    New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                } else {
                    Copy-Item -Path $_.FullName -Destination $destPath -Force
                }
            }

            Write-PodeJsonResponse -Value @{ success = $true; message = "Module '$moduleName' v$moduleVersion installed from GitHub" }
        } catch {
            Write-PodeJsonResponse -Value @{ success = $false; message = "GitHub install failed: $($_.Exception.Message)" } -StatusCode 500
        } finally {
            if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
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
                        # Skip if already running
                        $running = Get-PodeState -Name 'RunningWorkflows'
                        if (-not $running.TryAdd($schedule.workflow, [byte]0)) {
                            Write-EngineLog "SCHEDULE SKIP: '$($schedule.workflow)' — already running" 'WARN'
                            Write-Host "Skipping scheduled run of '$($schedule.workflow)' — already running" -ForegroundColor Yellow
                            continue
                        }
                        Write-EngineLog "SCHEDULE FIRED: '$($schedule.workflow)' from $($blob.Name)"
                        try {
                            # Run the workflow
                            & './Scripts/PODE/RunWorkflow.ps1' -Name $schedule.workflow | Out-Null
                            Write-EngineLog "SCHEDULE COMPLETE: '$($schedule.workflow)'"
                        } finally {
                            [void]$running.TryRemove($schedule.workflow, [ref][byte]0)
                        }

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
