# Execute a workflow — sequential step ladder
# Downloads each script from blob, runs it with translated params, captures output, chains to next step
param(
    [Parameter(Mandatory)] [string]$Name
)

$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
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

$capturedOutputs = @{}  # Variable store for output chaining between steps

$allPassed = $true

for ($i = 0; $i -lt $steps.Count; $i++) {
    $step = $steps[$i]
    $stepLog = @{
        index   = $i + 1
        type    = $step.type
        script  = $step.script
        webhook = $step.webhook
        status  = 'running'
        output  = ''
        error   = ''
    }

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

        switch ($step.type) {
            'powershell' {
                # Download script from nexus-powershell container
                $scriptContent = Read-Blob -Container 'nexus-powershell' -BlobPath $step.script
                if (-not $scriptContent) { throw "Script '$($step.script)' not found in nexus-powershell" }

                $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) "nexus-ps-$timestamp-$i.ps1"
                try {
                    [System.IO.File]::WriteAllText($tempScript, $scriptContent, [System.Text.Encoding]::UTF8)
                    # Build splatted params
                    if ($params.Count -gt 0) {
                        $output = & $tempScript @params 2>&1 | Out-String
                    } else {
                        $output = & $tempScript 2>&1 | Out-String
                    }
                } finally {
                    if (Test-Path $tempScript) { Remove-Item $tempScript -Force -ErrorAction SilentlyContinue }
                }
            }

            'terraform' {
                # Download terraform files from nexus-terraform container
                $tfDir = Join-Path ([System.IO.Path]::GetTempPath()) "nexus-tf-$timestamp-$i"
                New-Item -Path $tfDir -ItemType Directory -Force | Out-Null

                try {
                    # Download the specified plan/file
                    $tfContent = Read-Blob -Container 'nexus-terraform' -BlobPath $step.script
                    if (-not $tfContent) { throw "Terraform file '$($step.script)' not found in nexus-terraform" }

                    $tfFile = Join-Path $tfDir $step.script
                    [System.IO.File]::WriteAllText($tfFile, $tfContent, [System.Text.Encoding]::UTF8)

                    # Write KV params as .tfvars
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
                        $initOutput = terraform init -no-color 2>&1 | Out-String
                        $applyOutput = terraform apply -auto-approve -no-color 2>&1 | Out-String
                        $output = "$initOutput`n$applyOutput"

                        # Capture terraform output as JSON
                        try {
                            $tfOutputJson = terraform output -json 2>&1 | Out-String
                            $output += "`n--- Terraform Outputs ---`n$tfOutputJson"
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

                    # Pass params as command-line args: --key value
                    $argList = @($tempScript)
                    foreach ($key in $params.Keys) {
                        $argList += "--$key"
                        $argList += $params[$key]
                    }
                    $output = & python3 @argList 2>&1 | Out-String
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

                    # Pass params as environment variables
                    foreach ($key in $params.Keys) {
                        [System.Environment]::SetEnvironmentVariable($key, $params[$key])
                    }
                    $output = & bash $tempScript 2>&1 | Out-String
                } finally {
                    # Clean up env vars
                    foreach ($key in $params.Keys) {
                        [System.Environment]::SetEnvironmentVariable($key, $null)
                    }
                    if (Test-Path $tempScript) { Remove-Item $tempScript -Force -ErrorAction SilentlyContinue }
                }
            }

            'webhook' {
                # Load webhook config
                $whContent = Read-Blob -Container 'nexus-webhooks' -BlobPath "$($step.webhook).json"
                if (-not $whContent) { throw "Webhook '$($step.webhook)' not found" }
                $wh = $whContent | ConvertFrom-Json

                $headers = @{ 'Content-Type' = 'application/json' }

                # OAuth if needed
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

                # Pass KV params as JSON body (hashtable)
                $body = $params
                $bodyJson = $body | ConvertTo-Json -Depth 10

                $response = Invoke-RestMethod -Method Post -Uri $wh.uri -Headers $headers -Body $bodyJson -ContentType 'application/json'
                $output = $response | ConvertTo-Json -Depth 10
            }
        }

        # Capture outputs for chaining
        if ($step.outputCapture) {
            foreach ($oc in @($step.outputCapture)) {
                if (![string]::IsNullOrWhiteSpace($oc.key) -and ![string]::IsNullOrWhiteSpace($oc.as)) {
                    try {
                        # Try to parse output as JSON and extract the key
                        $parsed = $output | ConvertFrom-Json -ErrorAction Stop
                        $val = $parsed.$($oc.key)
                        if ($null -ne $val) {
                            $varName = "step$($i + 1).$($oc.as)"
                            $capturedOutputs[$varName] = [string]$val
                        }
                    } catch {
                        # If output isn't JSON, try regex extraction
                        if ($output -match "$($oc.key)\s*[:=]\s*(.+)") {
                            $varName = "step$($i + 1).$($oc.as)"
                            $capturedOutputs[$varName] = $Matches[1].Trim()
                        }
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
    }

    $stepLog.duration = [math]::Round(((Get-Date) - $stepStartTime).TotalSeconds, 2)
    $runLog.steps += $stepLog

    # Stop on failure — linear ladder doesn't continue past a failed step
    if ($stepLog.status -eq 'failed') {
        break
    }
}

$runLog.endTime = (Get-Date).ToString('o')
$runLog.status = if ($allPassed) { 'success' } else { 'failed' }

# Save run log to the per-workflow container
try {
    $logJson = $runLog | ConvertTo-Json -Depth 20
    Write-Blob -Container $logContainerName -BlobPath "logs/run-$timestamp.json" -Content $logJson
} catch {
    Write-Host "Failed to save run log: $($_.Exception.Message)" -ForegroundColor Red
}

$statusMsg = if ($allPassed) { "Workflow '$Name' completed successfully ($($steps.Count) steps)" } else { "Workflow '$Name' failed at step $($runLog.steps.Count)" }
return @{
    success = $allPassed
    message = $statusMsg
}
