# Execute a workflow — sequential step ladder
# Downloads each script from blob, runs it with translated params, captures output, chains to next step
param(
    [Parameter(Mandatory)] [string]$Name,
    [int]$StepIndex = -1   # -1 = run all steps; 0-based index = run single step only
)

# Engine log helper (daily rotation — matches Server.ps1 pattern)
function Get-EngineLogFile {
    return Join-Path ([System.IO.Path]::GetTempPath()) "nexus-engine-$(Get-Date -Format 'yyyy-MM-dd').log"
}
function Write-EngineLog {
    param([string]$Message, [string]$Level = 'INFO')
    $logFile = Get-EngineLogFile
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message`n"
    try { [System.IO.File]::AppendAllText($logFile, $line, [System.Text.Encoding]::UTF8) } catch { }
}

$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$isSingleStep = $StepIndex -ge 0
$logBaseName = if ($isSingleStep) { "$Name-step$($StepIndex + 1)-$timestamp" } else { "$Name-$timestamp" }
$logContainerName = ($Name -replace '[^a-z0-9-]', '-').ToLower()

$runLabel = if ($isSingleStep) { "TEST-STEP $($StepIndex + 1)" } else { 'FULL RUN' }
Write-EngineLog "WORKFLOW START: '$Name' ($runLabel, run: $logBaseName, steps: pending)"

# Ensure log container exists
try {
    $ctx = Get-AppStorageContext
    $existing = Get-AzStorageContainer -Name $logContainerName -Context $ctx -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-AzStorageContainer -Name $logContainerName -Context $ctx -Permission Off | Out-Null
    }
} catch { }

# Load workflow definition
$wfContent = Read-Blob -Container 'nexus-config' -BlobPath "workflows/$Name.json"
if (-not $wfContent) {
    return @{ success = $false; message = "Workflow '$Name' not found"; statusCode = 404 }
}

$workflow = $wfContent | ConvertFrom-Json
$steps = @($workflow.steps)
if ($isSingleStep -and ($StepIndex -ge $steps.Count)) {
    return @{ success = $false; message = "Step index $StepIndex is out of range (workflow has $($steps.Count) steps)"; statusCode = 400 }
}
Write-EngineLog "WORKFLOW LOADED: '$Name' — $($steps.Count) steps$(if ($isSingleStep) { " (testing step $($StepIndex + 1) only)" })"

$runLog = @{
    workflow  = $Name
    startTime = (Get-Date).ToString('o')
    status    = 'running'
    steps     = @()
}

# Collect all stdout and stderr across steps
$allOutput = [System.Text.StringBuilder]::new()
$allErrors = [System.Text.StringBuilder]::new()
$allInfo   = [System.Text.StringBuilder]::new()  # Write-Host / Information stream (PowerShell steps only)

# Live console temp file — frontend polls this for real-time output
$consoleTempFile = Join-Path ([System.IO.Path]::GetTempPath()) "nexus-console-$($Name.ToLower()).log"
$consoleHeader = if ($isSingleStep) { "========== TEST STEP $($StepIndex + 1): $logBaseName ==========" } else { "========== RUN: $logBaseName ==========" }
[void]$allOutput.AppendLine("@@HDR@@$consoleHeader")
[void]$allOutput.AppendLine("")
[System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8)

$capturedOutputs = @{}  # Variable store for output chaining between steps

$allPassed = $true

$startStep = if ($isSingleStep) { $StepIndex } else { 0 }
$endStep   = if ($isSingleStep) { $StepIndex + 1 } else { $steps.Count }

for ($i = $startStep; $i -lt $endStep; $i++) {
    $step = $steps[$i]
    $stepLabel = "Step $($i + 1): [$($step.type)] $($step.script)$($step.webhook)$($step.filecheck)"
    $stepLog = @{
        index   = $i + 1
        type    = $step.type
        script  = $step.script
        webhook = $step.webhook
        filecheck = $step.filecheck
        command = ''
        status  = 'running'
        output  = ''
        error   = ''
    }

    [void]$allOutput.AppendLine("@@HDR@@=========================================")
    [void]$allOutput.AppendLine("@@HDR@@  $stepLabel")
    [void]$allOutput.AppendLine("@@HDR@@=========================================")
    [void]$allOutput.AppendLine("")

    # Update live console so user sees step header immediately
    try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }

    $stepStartTime = Get-Date
    Write-EngineLog "STEP START: '$Name' $stepLabel"

    try {
        # Build parameters from KV pairs + input mappings
        $params = @{}

        # Static key/value params
        if ($step.params) {
            foreach ($kv in @($step.params)) {
                if (![string]::IsNullOrWhiteSpace($kv.key)) {
                    $params[$kv.key] = $kv.value
                }
            }
        }

        # Input mappings from captured outputs (e.g. "step1.runId")
        if ($step.inputMapping) {
            foreach ($im in @($step.inputMapping)) {
                if (![string]::IsNullOrWhiteSpace($im.key) -and ![string]::IsNullOrWhiteSpace($im.from)) {
                    if ($capturedOutputs.ContainsKey($im.from)) {
                        $params[$im.key] = $capturedOutputs[$im.from]
                    }
                }
            }
        }

        $output = $null
        $stdOut = $null
        $stdErr = $null
        $stdInfo = $null
        $stdVerbose = $null

        # Build human-readable command string for logging
        $commandStr = switch ($step.type) {
            'powershell' {
                $paramStr = ($params.GetEnumerator() | ForEach-Object { "-$($_.Key) $($_.Value)" }) -join ' '
                "& ./$($step.script)$(if ($paramStr) { " $paramStr" })"
            }
            'python' {
                $argStr = ($params.GetEnumerator() | ForEach-Object { "--$($_.Key) $($_.Value)" }) -join ' '
                "python3 $($step.script)$(if ($argStr) { " $argStr" })"
            }
            'shell' {
                $envStr = ($params.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '
                "$(if ($envStr) { "$envStr " })bash ./$($step.script)"
            }
            'terraform' {
                $varStr = ($params.GetEnumerator() | ForEach-Object { "-var `"$($_.Key)=$($_.Value)`"" }) -join ' '
                "terraform apply -auto-approve $($step.script)$(if ($varStr) { " $varStr" })"
            }
            'webhook' {
                $bodyPreview = if ($params.Count -gt 0) { ($params | ConvertTo-Json -Depth 5 -Compress) } else { '{}' }
                "POST $($step.webhook) | Body: $bodyPreview"
            }
            'filecheck' {
                "FileCheck $($step.filecheck) | Container: $($params['container']) Path: $($params['folderPath']) Timeout: $($params['timeout'])m"
            }
        }

        # Log command to console, engine log, and step log before execution
        if ($commandStr) {
            $stepLog.command = $commandStr
            [void]$allOutput.AppendLine("@@CMD@@  > $commandStr")
            [void]$allOutput.AppendLine("")
            try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }
            Write-EngineLog "STEP EXEC: '$Name' $stepLabel — $commandStr"
        }

        switch ($step.type) {
            'powershell' {
                $scriptContent = Read-Blob -Container 'nexus-powershell' -BlobPath $step.script
                if (-not $scriptContent) { throw "Script '$($step.script)' not found in nexus-powershell" }

                $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) "nexus-ps-$timestamp-$i.ps1"
                try {
                    [System.IO.File]::WriteAllText($tempScript, $scriptContent, [System.Text.Encoding]::UTF8)
                    # Stream stdout, stderr, information, and verbose line-by-line to the live console
                    $stdOutLines     = @()
                    $stdErrLines     = @()
                    $stdInfoLines    = @()
                    $stdVerboseLines = @()
                    $streamBlock = {
                        if ($_ -is [System.Management.Automation.ErrorRecord]) {
                            $stdErrLines += $_.ToString()
                            [void]$allOutput.AppendLine("@@ERR@@$($_.ToString())")
                        } elseif ($_ -is [System.Management.Automation.InformationRecord]) {
                            $stdInfoLines += $_.MessageData.ToString()
                            [void]$allOutput.AppendLine("@@INFO@@$($_.MessageData.ToString())")
                        } elseif ($_ -is [System.Management.Automation.VerboseRecord]) {
                            $stdVerboseLines += $_.Message
                            [void]$allOutput.AppendLine("@@VERBOSE@@$($_.Message)")
                        } else {
                            $stdOutLines += $_.ToString()
                            [void]$allOutput.AppendLine("@@OUT@@$($_.ToString())")
                        }
                        try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }
                    }
                    if ($params.Count -gt 0) {
                        & $tempScript @params 4>&1 6>&1 2>&1 | ForEach-Object $streamBlock
                    } else {
                        & $tempScript 4>&1 6>&1 2>&1 | ForEach-Object $streamBlock
                    }
                    $stdOut     = $stdOutLines     -join "`n"
                    $stdErr     = $stdErrLines     -join "`n"
                    $stdInfo    = $stdInfoLines    -join "`n"
                    $stdVerbose = $stdVerboseLines -join "`n"
                    $output     = $stdOut
                } finally {
                    if (Test-Path $tempScript) { Remove-Item $tempScript -Force -ErrorAction SilentlyContinue }
                }
            }

            'terraform' {
                $tfDir = Join-Path ([System.IO.Path]::GetTempPath()) "nexus-tf-$timestamp-$i"
                New-Item -Path $tfDir -ItemType Directory -Force | Out-Null

                try {
                    $tfContent = Read-Blob -Container 'nexus-terraform' -BlobPath $step.script
                    if (-not $tfContent) { throw "Terraform file '$($step.script)' not found in nexus-terraform" }

                    $tfFile = Join-Path $tfDir $step.script
                    [System.IO.File]::WriteAllText($tfFile, $tfContent, [System.Text.Encoding]::UTF8)

                    if ($params.Count -gt 0) {
                        $tfvarsLines = @()
                        foreach ($key in $params.Keys) {
                            $tfvarsLines += "$key = `"$($params[$key])`""
                        }
                        $tfvarsPath = Join-Path $tfDir "nexus.auto.tfvars"
                        $tfvarsLines | Set-Content -Path $tfvarsPath
                    }

                    Push-Location $tfDir
                    try {
                        $stdOutLines = @()
                        $tfStreamBlock = {
                            $ln = $_.ToString()
                            $stdOutLines += $ln
                            [void]$allOutput.AppendLine("@@OUT@@$ln")
                            try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }
                        }
                        terraform init -no-color 2>&1 | ForEach-Object $tfStreamBlock
                        terraform apply -auto-approve -no-color 2>&1 | ForEach-Object $tfStreamBlock
                        $stdOut = $stdOutLines -join "`n"
                        $output = $stdOut

                        try {
                            $tfOutputJson = terraform output -json 2>&1 | Out-String
                            $output += "`n--- Terraform Outputs ---`n$tfOutputJson"
                            $stdOut += "`n--- Terraform Outputs ---`n$tfOutputJson"
                            [void]$allOutput.AppendLine("@@OUT@@--- Terraform Outputs ---")
                            foreach ($ln in $tfOutputJson -split "`n") { [void]$allOutput.AppendLine("@@OUT@@$ln") }
                            try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }
                        } catch { }
                    } finally {
                        Pop-Location
                    }
                } finally {
                    if (Test-Path $tfDir) { Remove-Item $tfDir -Recurse -Force -ErrorAction SilentlyContinue }
                }
            }

            'python' {
                $scriptContent = Read-Blob -Container 'nexus-python' -BlobPath $step.script
                if (-not $scriptContent) { throw "Script '$($step.script)' not found in nexus-python" }

                $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) "nexus-py-$timestamp-$i.py"
                try {
                    [System.IO.File]::WriteAllText($tempScript, $scriptContent, [System.Text.Encoding]::UTF8)

                    $argList = @($tempScript)
                    foreach ($key in $params.Keys) {
                        $argList += "--$key"
                        $argList += $params[$key]
                    }
                    $stdOutLines = @()
                    $stdErrLines = @()
                    & python3 @argList 2>&1 | ForEach-Object {
                        if ($_ -is [System.Management.Automation.ErrorRecord]) {
                            $stdErrLines += $_.ToString()
                            [void]$allOutput.AppendLine("@@ERR@@$($_.ToString())")
                        } else {
                            $stdOutLines += $_.ToString()
                            [void]$allOutput.AppendLine("@@OUT@@$($_.ToString())")
                        }
                        try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }
                    }
                    $stdOut = $stdOutLines -join "`n"
                    $stdErr = $stdErrLines -join "`n"
                    $output = $stdOut
                } finally {
                    if (Test-Path $tempScript) { Remove-Item $tempScript -Force -ErrorAction SilentlyContinue }
                }
            }

            'shell' {
                $scriptContent = Read-Blob -Container 'nexus-shell' -BlobPath $step.script
                if (-not $scriptContent) { throw "Script '$($step.script)' not found in nexus-shell" }

                $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) "nexus-sh-$timestamp-$i.sh"
                try {
                    [System.IO.File]::WriteAllText($tempScript, $scriptContent, [System.Text.Encoding]::UTF8)
                    & chmod +x $tempScript 2>$null

                    foreach ($key in $params.Keys) {
                        [System.Environment]::SetEnvironmentVariable($key, $params[$key])
                    }
                    $stdOutLines = @()
                    $stdErrLines = @()
                    & bash $tempScript 2>&1 | ForEach-Object {
                        if ($_ -is [System.Management.Automation.ErrorRecord]) {
                            $stdErrLines += $_.ToString()
                            [void]$allOutput.AppendLine("@@ERR@@$($_.ToString())")
                        } else {
                            $stdOutLines += $_.ToString()
                            [void]$allOutput.AppendLine("@@OUT@@$($_.ToString())")
                        }
                        try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }
                    }
                    $stdOut = $stdOutLines -join "`n"
                    $stdErr = $stdErrLines -join "`n"
                    $output = $stdOut
                } finally {
                    foreach ($key in $params.Keys) {
                        [System.Environment]::SetEnvironmentVariable($key, $null)
                    }
                    if (Test-Path $tempScript) { Remove-Item $tempScript -Force -ErrorAction SilentlyContinue }
                }
            }

            'webhook' {
                $whContent = Read-Blob -Container 'nexus-webhooks' -BlobPath "$($step.webhook).json"
                if (-not $whContent) { throw "Webhook '$($step.webhook)' not found" }
                $wh = $whContent | ConvertFrom-Json

                # Update command string with actual URI now that webhook config is loaded
                $bodyPreview = if ($params.Count -gt 0) { ($params | ConvertTo-Json -Depth 5 -Compress) } else { '{}' }
                $stepLog.command = "POST $($wh.uri) | Body: $bodyPreview"

                $headers = @{ 'Content-Type' = 'application/json' }

                if ($wh.authType -eq 'oauth') {
                    $tokenBody = @{
                        grant_type    = 'client_credentials'
                        client_id     = $wh.clientId
                        client_secret = $wh.clientSecret
                        scope         = 'https://management.azure.com/.default'
                    }
                    $tokenUrl = "https://login.microsoftonline.com/$($wh.tenantId)/oauth2/v2.0/token"
                    $tokenResp = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $tokenBody -ContentType 'application/x-www-form-urlencoded'
                    $headers['Authorization'] = "Bearer $($tokenResp.access_token)"
                }

                $body = $params
                $bodyJson = $body | ConvertTo-Json -Depth 10

                $response = Invoke-RestMethod -Method Post -Uri $wh.uri -Headers $headers -Body $bodyJson -ContentType 'application/json'
                $stdOut = $response | ConvertTo-Json -Depth 10
                $output = $stdOut
                foreach ($ln in $stdOut -split "`n") { [void]$allOutput.AppendLine("@@OUT@@$ln") }
                try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }
            }

            'filecheck' {
                # Load file check configuration
                $fcContent = Read-Blob -Container 'nexus-config' -BlobPath "filechecks/$($step.filecheck).json"
                if (-not $fcContent) { throw "File Check '$($step.filecheck)' not found" }
                $fc = $fcContent | ConvertFrom-Json

                # Update command string with storage account from config
                $stepLog.command = "FileCheck $($step.filecheck) | Account: $($fc.storageAccount) Container: $($params['container']) Path: $($params['folderPath']) Timeout: $($params['timeout'])m"

                # Get params: container, folderPath, timeout
                $containerName = $params['container']
                $folderPath = $params['folderPath']
                $timeoutMinutes = [int]($params['timeout'])
                if ([string]::IsNullOrWhiteSpace($containerName)) { throw "File Check requires 'container' parameter" }
                if ($timeoutMinutes -le 0) { $timeoutMinutes = 5 }

                # Build storage context based on auth type
                $fcCtx = $null
                if ($fc.authType -eq 'sas') {
                    $fcCtx = New-AzStorageContext -StorageAccountName $fc.storageAccount -SasToken $fc.sasToken
                } else {
                    # RBAC — use the already-connected service principal
                    $fcCtx = New-AzStorageContext -StorageAccountName $fc.storageAccount -UseConnectedAccount
                }

                # Normalize folder path prefix
                $prefix = if (![string]::IsNullOrWhiteSpace($folderPath)) {
                    $folderPath.TrimStart('/').TrimEnd('/') + '/'
                } else { $null }

                # Snapshot the current file state (last-modified times)
                $baselineBlobs = @{}
                try {
                    $existingBlobs = if ($prefix) {
                        Get-AzStorageBlob -Container $containerName -Prefix $prefix -Context $fcCtx -ErrorAction Stop
                    } else {
                        Get-AzStorageBlob -Container $containerName -Context $fcCtx -ErrorAction Stop
                    }
                    foreach ($b in $existingBlobs) {
                        $baselineBlobs[$b.Name] = $b.LastModified
                    }
                } catch {
                    # Empty container or path — baseline is empty
                }

                $stepStartCheck = Get-Date
                $deadline = $stepStartCheck.AddMinutes($timeoutMinutes)
                $newFiles = @()

                [void]$allOutput.AppendLine("@@INFO@@  Polling $($fc.storageAccount)/$containerName/$prefix every 30s (timeout: ${timeoutMinutes}m)...")
                try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }

                while ((Get-Date) -lt $deadline) {
                    Start-Sleep -Seconds 30

                    try {
                        $currentBlobs = if ($prefix) {
                            Get-AzStorageBlob -Container $containerName -Prefix $prefix -Context $fcCtx -ErrorAction Stop
                        } else {
                            Get-AzStorageBlob -Container $containerName -Context $fcCtx -ErrorAction Stop
                        }
                    } catch {
                        [void]$allOutput.AppendLine("@@ERR@@  Poll error: $($_.Exception.Message)")
                        try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }
                        continue
                    }

                    $newFiles = @()
                    foreach ($b in $currentBlobs) {
                        if (-not $baselineBlobs.ContainsKey($b.Name)) {
                            # Brand new file
                            $newFiles += "$containerName/$($b.Name)"
                        } elseif ($b.LastModified -gt $baselineBlobs[$b.Name]) {
                            # Updated file
                            $newFiles += "$containerName/$($b.Name)"
                        }
                    }

                    if ($newFiles.Count -gt 0) {
                        [void]$allOutput.AppendLine("@@INFO@@  Detected $($newFiles.Count) new/updated file(s)")
                        break
                    }

                    $remaining = [math]::Round(($deadline - (Get-Date)).TotalSeconds)
                    [void]$allOutput.AppendLine("@@INFO@@  No changes yet... ${remaining}s remaining")
                    try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }
                }

                if ($newFiles.Count -eq 0) {
                    throw "File Check timed out after ${timeoutMinutes} minute(s) — no new files detected in $($fc.storageAccount)/$containerName/$prefix"
                }

                # Build output JSON
                $resultObj = @{ files = $newFiles }
                $stdOut = $resultObj | ConvertTo-Json -Depth 10
                $output = $stdOut
                foreach ($ln in $stdOut -split "`n") { [void]$allOutput.AppendLine("@@OUT@@$ln") }
                try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }
            }
        }

        # Write remaining streams to blob logs (console was already updated live)
        if ($stdInfo) {
            [void]$allInfo.AppendLine("=========================================")
            [void]$allInfo.AppendLine("  $stepLabel")
            [void]$allInfo.AppendLine("=========================================")
            [void]$allInfo.AppendLine($stdInfo)
            [void]$allInfo.AppendLine("")
        }
        if ($stdErr) {
            [void]$allErrors.AppendLine("=========================================")
            [void]$allErrors.AppendLine("  $stepLabel")
            [void]$allErrors.AppendLine("=========================================")
            [void]$allErrors.AppendLine($stdErr)
        }
        [void]$allOutput.AppendLine("")

        # Update live console temp file
        try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }

        # Auto-register ALL JSON properties from output as step{N}.{key}
        # Strategy: try full output first, then scan backward for last JSON block
        $parsed = $null
        $jsonExtracted = $false

        if (![string]::IsNullOrWhiteSpace($output)) {
            # Fast path: entire output is valid JSON
            try {
                $parsed = $output | ConvertFrom-Json -ErrorAction Stop
                $jsonExtracted = $true
            } catch {
                # Slow path: scan backward from the end for the last JSON object/array
                $lines = $output -split "`n"
                for ($j = $lines.Count - 1; $j -ge 0; $j--) {
                    $trimmed = $lines[$j].Trim()
                    if ($trimmed -eq '}' -or $trimmed -eq ']') {
                        # Found a potential JSON closing — find its opener
                        $closer = $trimmed
                        $opener = if ($closer -eq '}') { '{' } else { '[' }
                        $depth = 0
                        for ($k = $j; $k -ge 0; $k--) {
                            foreach ($ch in $lines[$k].ToCharArray()) {
                                if ($ch -eq $closer[0]) { $depth++ }
                                elseif ($ch -eq $opener[0]) { $depth-- }
                            }
                            if ($depth -eq 0) {
                                $candidate = ($lines[$k..$j]) -join "`n"
                                try {
                                    $parsed = $candidate | ConvertFrom-Json -ErrorAction Stop
                                    $jsonExtracted = $true
                                    break
                                } catch {
                                    # Not valid JSON at this position, keep scanning
                                }
                            }
                        }
                        if ($jsonExtracted) { break }
                    }
                }
            }
        }

        if ($jsonExtracted -and $parsed) {
            foreach ($prop in $parsed.PSObject.Properties) {
                $varName = "step$($i + 1).$($prop.Name)"
                $capturedOutputs[$varName] = [string]$prop.Value
            }
        }

        # Breakpoint checks — validate required properties in output
        $needsJson = $false
        if ($step.breakpointChecks) {
            $needsJson = $true
            if (-not $jsonExtracted) {
                throw "Breakpoint failed: step $($i + 1) expected a JSON response but none was found in the script output. Please review the script to ensure it outputs valid JSON."
            }
            foreach ($bp in @($step.breakpointChecks)) {
                if (![string]::IsNullOrWhiteSpace($bp.key)) {
                    $actualValue = $capturedOutputs["step$($i + 1).$($bp.key)"]
                    if ($null -eq $actualValue) {
                        throw "Breakpoint failed: step $($i + 1) output missing property '$($bp.key)'"
                    }
                    if (![string]::IsNullOrWhiteSpace($bp.value) -and $actualValue -ne $bp.value) {
                        throw "Breakpoint failed: step $($i + 1) property '$($bp.key)' expected '$($bp.value)' but got '$actualValue'"
                    }
                }
            }
        }

        $stepLog.output = $output
        $stepLog.status = 'success'

    } catch {
        $stepLog.status = 'failed'
        $stepLog.error = $_.Exception.Message
        $allPassed = $false
        Write-EngineLog "STEP FAILED: '$Name' $stepLabel — $($_.Exception.Message)" 'ERROR'

        # Log the exception
        [void]$allErrors.AppendLine("=========================================")
        [void]$allErrors.AppendLine("  $stepLabel — EXCEPTION")
        [void]$allErrors.AppendLine("=========================================")
        [void]$allErrors.AppendLine($_.Exception.Message)

        # Include full stack trace for deeper debugging
        if ($_.Exception.StackTrace) {
            [void]$allErrors.AppendLine("")
            [void]$allErrors.AppendLine("--- Stack Trace ---")
            [void]$allErrors.AppendLine($_.Exception.StackTrace)
        }
        if ($_.Exception.InnerException) {
            [void]$allErrors.AppendLine("")
            [void]$allErrors.AppendLine("--- Inner Exception ---")
            [void]$allErrors.AppendLine($_.Exception.InnerException.Message)
        }

        # Include any non-terminating errors (stderr) captured before the exception
        if (![string]::IsNullOrWhiteSpace($stdErr)) {
            [void]$allErrors.AppendLine("")
            [void]$allErrors.AppendLine("--- Script Error Stream (non-terminating) ---")
            [void]$allErrors.AppendLine($stdErr)
        }

        # Include $Error variable — catches module-level errors not surfaced by 2>&1
        $sessionErrors = $Error | Where-Object { $_ -ne $null } | Select-Object -First 10
        if ($sessionErrors) {
            [void]$allErrors.AppendLine("")
            [void]$allErrors.AppendLine("--- `$Error (session, last 10) ---")
            foreach ($e in $sessionErrors) {
                [void]$allErrors.AppendLine("  $($e.ToString())")
                if ($e.ScriptStackTrace) {
                    [void]$allErrors.AppendLine("    at: $($e.ScriptStackTrace -replace "`n", "`n    at: ")")
                }
            }
        }

        [void]$allErrors.AppendLine("")

        [void]$allOutput.AppendLine("@@ERR@@FAILED: $($_.Exception.Message)")
        if ($_.Exception.InnerException) {
            [void]$allOutput.AppendLine("@@ERR@@  Inner: $($_.Exception.InnerException.Message)")
        }
        if (![string]::IsNullOrWhiteSpace($stdErr)) {
            [void]$allOutput.AppendLine("")
            [void]$allOutput.AppendLine("@@ERR@@--- Script Error Stream ---")
            foreach ($ln in $stdErr -split "`n") { [void]$allOutput.AppendLine("@@ERR@@$ln") }
        }
        [void]$allOutput.AppendLine("")

        # Update live console temp file on failure too
        try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }
    }

    $stepLog.duration = [math]::Round(((Get-Date) - $stepStartTime).TotalSeconds, 2)
    $runLog.steps += $stepLog
    if ($stepLog.status -eq 'success') { Write-EngineLog "STEP DONE: '$Name' $stepLabel — $($stepLog.duration)s" }

    # Stop on failure
    if ($stepLog.status -eq 'failed') {
        break
    }
}

$runLog.endTime = (Get-Date).ToString('o')
$runLog.status = if ($allPassed) { 'success' } else { 'failed' }

# Save output log: {workflowname}-{timestamp}.json
try {
    $logJson = $runLog | ConvertTo-Json -Depth 20
    Write-Blob -Container $logContainerName -BlobPath "logs/$logBaseName.json" -Content $logJson
} catch {
    Write-Host "Failed to save run log: $($_.Exception.Message)" -ForegroundColor Red
}

# Save full text output log
try {
    $outputText = $allOutput.ToString()
    if (![string]::IsNullOrWhiteSpace($outputText)) {
        Write-Blob -Container $logContainerName -BlobPath "logs/$logBaseName-output.log" -Content $outputText
    }
} catch {
    Write-Host "Failed to save output log: $($_.Exception.Message)" -ForegroundColor Red
}

# Save error log if any errors occurred
try {
    $errorText = $allErrors.ToString()
    if (![string]::IsNullOrWhiteSpace($errorText)) {
        Write-Blob -Container $logContainerName -BlobPath "logs/$logBaseName-error.log" -Content $errorText
    }
} catch {
    Write-Host "Failed to save error log: $($_.Exception.Message)" -ForegroundColor Red
}

# Save information stream log (Write-Host output from PowerShell steps)
try {
    $infoText = $allInfo.ToString()
    if (![string]::IsNullOrWhiteSpace($infoText)) {
        Write-Blob -Container $logContainerName -BlobPath "logs/$logBaseName-information.log" -Content $infoText
    }
} catch {
    Write-Host "Failed to save information log: $($_.Exception.Message)" -ForegroundColor Red
}

# Final update to live console temp file before it's done
try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }

$stepsRan = if ($isSingleStep) { "step $($StepIndex + 1)" } else { "$($steps.Count) steps" }
$statusMsg = if ($allPassed) {
    if ($isSingleStep) { "Test step $($StepIndex + 1) of '$Name' completed successfully" }
    else { "Workflow '$Name' completed successfully ($($steps.Count) steps)" }
} else {
    if ($isSingleStep) { "Test step $($StepIndex + 1) of '$Name' failed" }
    else { "Workflow '$Name' failed at step $($runLog.steps.Count)" }
}
Write-EngineLog "WORKFLOW END: '$Name' — $($runLog.status) — $statusMsg"
return @{
    success = $allPassed
    message = $statusMsg
}
