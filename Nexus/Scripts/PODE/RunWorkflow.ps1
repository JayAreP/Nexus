# Execute a workflow — sequential step ladder
# Downloads each script from blob, runs it with translated params, captures output, chains to next step
param(
    [Parameter(Mandatory)] [string]$Name
)

$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$logBaseName = "$Name-$timestamp"
$logContainerName = ($Name -replace '[^a-z0-9-]', '-').ToLower()

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

$runLog = @{
    workflow  = $Name
    startTime = (Get-Date).ToString('o')
    status    = 'running'
    steps     = @()
}

# Collect all stdout and stderr across steps
$allOutput = [System.Text.StringBuilder]::new()
$allErrors = [System.Text.StringBuilder]::new()

# Live console temp file — frontend polls this for real-time output
$consoleTempFile = Join-Path ([System.IO.Path]::GetTempPath()) "nexus-console-$($Name.ToLower()).log"
[System.IO.File]::WriteAllText($consoleTempFile, "", [System.Text.Encoding]::UTF8)

$capturedOutputs = @{}  # Variable store for output chaining between steps

$allPassed = $true

for ($i = 0; $i -lt $steps.Count; $i++) {
    $step = $steps[$i]
    $stepLabel = "Step $($i + 1): [$($step.type)] $($step.script)$($step.webhook)$($step.filecheck)"
    $stepLog = @{
        index   = $i + 1
        type    = $step.type
        script  = $step.script
        webhook = $step.webhook
        filecheck = $step.filecheck
        status  = 'running'
        output  = ''
        error   = ''
    }

    [void]$allOutput.AppendLine("=========================================")
    [void]$allOutput.AppendLine("  $stepLabel")
    [void]$allOutput.AppendLine("=========================================")

    # Update live console so user sees step header immediately
    try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }

    $stepStartTime = Get-Date

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

        switch ($step.type) {
            'powershell' {
                $scriptContent = Read-Blob -Container 'nexus-powershell' -BlobPath $step.script
                if (-not $scriptContent) { throw "Script '$($step.script)' not found in nexus-powershell" }

                $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) "nexus-ps-$timestamp-$i.ps1"
                try {
                    [System.IO.File]::WriteAllText($tempScript, $scriptContent, [System.Text.Encoding]::UTF8)
                    # Capture stdout and stderr separately
                    $rawOutput = if ($params.Count -gt 0) {
                        & $tempScript @params 2>&1
                    } else {
                        & $tempScript 2>&1
                    }
                    # Separate stdout from stderr
                    $stdOutLines = @()
                    $stdErrLines = @()
                    foreach ($line in $rawOutput) {
                        if ($line -is [System.Management.Automation.ErrorRecord]) {
                            $stdErrLines += $line.ToString()
                        } else {
                            $stdOutLines += $line.ToString()
                        }
                    }
                    $stdOut = $stdOutLines -join "`n"
                    $stdErr = $stdErrLines -join "`n"
                    $output = $stdOut
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
                        $rawInit = terraform init -no-color 2>&1
                        $rawApply = terraform apply -auto-approve -no-color 2>&1
                        $stdOut = ($rawInit + $rawApply) | Out-String
                        $output = $stdOut

                        try {
                            $tfOutputJson = terraform output -json 2>&1 | Out-String
                            $output += "`n--- Terraform Outputs ---`n$tfOutputJson"
                            $stdOut += "`n--- Terraform Outputs ---`n$tfOutputJson"
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
                    $rawOutput = & python3 @argList 2>&1
                    $stdOutLines = @()
                    $stdErrLines = @()
                    foreach ($line in $rawOutput) {
                        if ($line -is [System.Management.Automation.ErrorRecord]) {
                            $stdErrLines += $line.ToString()
                        } else {
                            $stdOutLines += $line.ToString()
                        }
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
                    $rawOutput = & bash $tempScript 2>&1
                    $stdOutLines = @()
                    $stdErrLines = @()
                    foreach ($line in $rawOutput) {
                        if ($line -is [System.Management.Automation.ErrorRecord]) {
                            $stdErrLines += $line.ToString()
                        } else {
                            $stdOutLines += $line.ToString()
                        }
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
            }

            'filecheck' {
                # Load file check configuration
                $fcContent = Read-Blob -Container 'nexus-config' -BlobPath "filechecks/$($step.filecheck).json"
                if (-not $fcContent) { throw "File Check '$($step.filecheck)' not found" }
                $fc = $fcContent | ConvertFrom-Json

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

                [void]$allOutput.AppendLine("  Polling $($fc.storageAccount)/$containerName/$prefix every 30s (timeout: ${timeoutMinutes}m)...")
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
                        [void]$allOutput.AppendLine("  Poll error: $($_.Exception.Message)")
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
                        [void]$allOutput.AppendLine("  Detected $($newFiles.Count) new/updated file(s)")
                        break
                    }

                    $remaining = [math]::Round(($deadline - (Get-Date)).TotalSeconds)
                    [void]$allOutput.AppendLine("  No changes yet... ${remaining}s remaining")
                    try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }
                }

                if ($newFiles.Count -eq 0) {
                    throw "File Check timed out after ${timeoutMinutes} minute(s) — no new files detected in $($fc.storageAccount)/$containerName/$prefix"
                }

                # Build output JSON
                $resultObj = @{ files = $newFiles }
                $stdOut = $resultObj | ConvertTo-Json -Depth 10
                $output = $stdOut
            }
        }

        # Append step output to full log
        if ($stdOut) { [void]$allOutput.AppendLine($stdOut) }
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

        # Log the error
        [void]$allErrors.AppendLine("=========================================")
        [void]$allErrors.AppendLine("  $stepLabel — EXCEPTION")
        [void]$allErrors.AppendLine("=========================================")
        [void]$allErrors.AppendLine($_.Exception.Message)
        [void]$allErrors.AppendLine("")

        [void]$allOutput.AppendLine("FAILED: $($_.Exception.Message)")
        [void]$allOutput.AppendLine("")

        # Update live console temp file on failure too
        try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }
    }

    $stepLog.duration = [math]::Round(((Get-Date) - $stepStartTime).TotalSeconds, 2)
    $runLog.steps += $stepLog

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

# Final update to live console temp file before it's done
try { [System.IO.File]::WriteAllText($consoleTempFile, $allOutput.ToString(), [System.Text.Encoding]::UTF8) } catch { }

$statusMsg = if ($allPassed) { "Workflow '$Name' completed successfully ($($steps.Count) steps)" } else { "Workflow '$Name' failed at step $($runLog.steps.Count)" }
return @{
    success = $allPassed
    message = $statusMsg
}
