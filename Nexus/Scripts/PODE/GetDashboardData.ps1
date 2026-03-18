# Aggregate dashboard data from all workflow run logs
# Returns: counts, running jobs, 24h stats, 7-day trend, leaderboards

$configPath = './conf/config.json'
if (-not (Test-Path $configPath)) {
    return @{ success = $false; message = "No configuration found" }
}

$cfg = Get-Content -Path $configPath -Raw | ConvertFrom-Json
try {
    $ctx = New-AzStorageContext -StorageAccountName $cfg.storageAccount -StorageAccountKey $cfg.key
} catch {
    return @{ success = $false; message = "Storage connection failed: $($_.Exception.Message)" }
}

$now = [datetime]::UtcNow

# ── Resource counts ───────────────────────────────────────────────────────────
try {
    $workflowBlobs = Get-AzStorageBlob -Container 'nexus-config' -Prefix 'workflows/' -Context $ctx -ErrorAction Stop | Where-Object { $_.Name -match '\.json$' }
    $workflowCount = @($workflowBlobs).Count
} catch { $workflowCount = 0 }

try {
    $scheduleBlobs = Get-AzStorageBlob -Container 'nexus-config' -Prefix 'schedules/' -Context $ctx -ErrorAction Stop | Where-Object { $_.Name -match '\.json$' }
    $scheduleCount = @($scheduleBlobs).Count
} catch { $scheduleCount = 0 }

$scriptCount = 0
foreach ($type in @('nexus-powershell', 'nexus-python', 'nexus-terraform', 'nexus-shell')) {
    try {
        $scripts = Get-AzStorageBlob -Container $type -Context $ctx -ErrorAction Stop
        $scriptCount += @($scripts).Count
    } catch { }
}

try {
    $webhookBlobs = Get-AzStorageBlob -Container 'nexus-config' -Prefix 'webhooks/' -Context $ctx -ErrorAction Stop | Where-Object { $_.Name -match '\.json$' }
    $webhookCount = @($webhookBlobs).Count
} catch { $webhookCount = 0 }

try {
    $filecheckBlobs = Get-AzStorageBlob -Container 'nexus-config' -Prefix 'filechecks/' -Context $ctx -ErrorAction Stop | Where-Object { $_.Name -match '\.json$' }
    $filecheckCount = @($filecheckBlobs).Count
} catch { $filecheckCount = 0 }

try {
    $credBlobs = Get-AzStorageBlob -Container 'nexus-credentials' -Context $ctx -ErrorAction Stop | Where-Object { $_.Name -match '\.json$' }
    $credentialCount = @($credBlobs).Count
} catch { $credentialCount = 0 }

# ── Currently running ─────────────────────────────────────────────────────────
$running = Get-PodeState -Name 'RunningWorkflows'
$runningList = @()
if ($running -and $running.Keys.Count -gt 0) {
    foreach ($name in $running.Keys) {
        $runningList += $name
    }
}

# ── Gather JSON run logs from all workflow containers ─────────────────────────
# Identify workflow containers by listing blobs associated with known workflows
$allRuns = [System.Collections.Generic.List[object]]::new()

# Get workflow names from config blobs, derive container names
$workflowNames = @()
try {
    foreach ($b in $workflowBlobs) {
        $content = Read-Blob -Container 'nexus-config' -BlobPath $b.Name
        if ($content) {
            $wf = $content | ConvertFrom-Json
            if ($wf.name) { $workflowNames += $wf.name }
        }
    }
} catch { }

# Only scan logs from the last 30 days to keep it fast
$cutoff30 = $now.AddDays(-30)

foreach ($wfName in $workflowNames) {
    $containerName = ($wfName -replace '[^a-z0-9-]', '-').ToLower()
    try {
        $logBlobs = Get-AzStorageBlob -Container $containerName -Prefix 'logs/' -Context $ctx -ErrorAction Stop |
            Where-Object { $_.Name -match '\.json$' -and $_.LastModified.UtcDateTime -ge $cutoff30 }
    } catch {
        continue
    }

    foreach ($blob in $logBlobs) {
        try {
            $tempFile = [System.IO.Path]::GetTempFileName()
            Get-AzStorageBlobContent -Container $containerName -Blob $blob.Name -Destination $tempFile -Context $ctx -Force -ErrorAction Stop | Out-Null
            $content = Get-Content -Path $tempFile -Raw
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            if (-not $content) { continue }
            $log = $content | ConvertFrom-Json
            if (-not $log.status -or -not $log.startTime) { continue }
            $allRuns.Add(@{
                workflow  = $log.workflow
                status    = $log.status
                startTime = [datetime]::Parse($log.startTime)
                endTime   = if ($log.endTime) { [datetime]::Parse($log.endTime) } else { $null }
                steps     = @($log.steps)
            })
        } catch {
            continue
        }
    }
}

# ── 24-hour stats ─────────────────────────────────────────────────────────────
$cutoff24h = $now.AddHours(-24)
$last24 = $allRuns | Where-Object { $_.startTime -ge $cutoff24h }
$total24      = @($last24).Count
$success24    = @($last24 | Where-Object { $_.status -eq 'success' }).Count
$failed24     = @($last24 | Where-Object { $_.status -eq 'failed' }).Count
$successRate  = if ($total24 -gt 0) { [math]::Round(($success24 / $total24) * 100, 1) } else { 0 }

$durations24 = @($last24 | Where-Object { $_.endTime } | ForEach-Object {
    ($_.endTime - $_.startTime).TotalSeconds
})
$avgDuration = if ($durations24.Count -gt 0) { [math]::Round(($durations24 | Measure-Object -Average).Average, 1) } else { 0 }
$longestRun  = $null
if ($durations24.Count -gt 0) {
    $longest = $last24 | Where-Object { $_.endTime } | Sort-Object { ($_.endTime - $_.startTime).TotalSeconds } -Descending | Select-Object -First 1
    if ($longest) {
        $longestRun = @{
            workflow = $longest.workflow
            duration = [math]::Round(($longest.endTime - $longest.startTime).TotalSeconds, 1)
        }
    }
}

# ── 7-day trend (daily buckets) ──────────────────────────────────────────────
$trend = @()
for ($i = 6; $i -ge 0; $i--) {
    $dayStart = ($now.Date).AddDays(-$i)
    $dayEnd   = $dayStart.AddDays(1)
    $dayRuns  = $allRuns | Where-Object { $_.startTime -ge $dayStart -and $_.startTime -lt $dayEnd }
    $trend += @{
        date    = $dayStart.ToString('yyyy-MM-dd')
        label   = $dayStart.ToString('ddd')
        success = @($dayRuns | Where-Object { $_.status -eq 'success' }).Count
        failed  = @($dayRuns | Where-Object { $_.status -eq 'failed' }).Count
    }
}

# ── Leaderboards (from all 30-day data) ──────────────────────────────────────
# Most-run workflows
$byWorkflow = $allRuns | Group-Object { $_.workflow }
$mostRun = @($byWorkflow | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object {
    @{ workflow = $_.Name; count = $_.Count }
})

# Most-failing workflows
$mostFailing = @($byWorkflow | ForEach-Object {
    $fails = @($_.Group | Where-Object { $_.status -eq 'failed' }).Count
    @{ workflow = $_.Name; failures = $fails; total = $_.Count; rate = if ($_.Count -gt 0) { [math]::Round(($fails / $_.Count) * 100, 1) } else { 0 } }
} | Where-Object { $_.failures -gt 0 } | Sort-Object { $_.failures } -Descending | Select-Object -First 5)

# Slowest workflows (by average duration)
$slowest = @($byWorkflow | ForEach-Object {
    $durs = @($_.Group | Where-Object { $_.endTime } | ForEach-Object { ($_.endTime - $_.startTime).TotalSeconds })
    if ($durs.Count -gt 0) {
        @{ workflow = $_.Name; avgDuration = [math]::Round(($durs | Measure-Object -Average).Average, 1); runs = $durs.Count }
    }
} | Where-Object { $_ } | Sort-Object { $_.avgDuration } -Descending | Select-Object -First 5)

# Recent failures
$recentFailures = @($allRuns | Where-Object { $_.status -eq 'failed' } | Sort-Object { $_.startTime } -Descending | Select-Object -First 5 | ForEach-Object {
    $ago = $now - $_.startTime
    $agoStr = if ($ago.TotalMinutes -lt 60) { "$([math]::Round($ago.TotalMinutes))m ago" }
              elseif ($ago.TotalHours -lt 24) { "$([math]::Round($ago.TotalHours, 1))h ago" }
              else { "$([math]::Round($ago.TotalDays, 1))d ago" }
    @{ workflow = $_.workflow; when = $agoStr; time = $_.startTime.ToString('yyyy-MM-dd HH:mm') }
})

# Step-level stats
$allSteps = $allRuns | ForEach-Object { $_.steps } | Where-Object { $_ }
$stepsByType = $allSteps | Group-Object { $_.type }
$stepTypeStats = @($stepsByType | ForEach-Object {
    $fails = @($_.Group | Where-Object { $_.status -eq 'failed' }).Count
    @{ type = $_.Name; total = $_.Count; failures = $fails }
})

# ── Return everything ─────────────────────────────────────────────────────────
return @{
    success = $true
    counts = @{
        workflows   = $workflowCount
        scripts     = $scriptCount
        schedules   = $scheduleCount
        webhooks    = $webhookCount
        filechecks  = $filecheckCount
        credentials = $credentialCount
    }
    running   = $runningList
    last24h   = @{
        total       = $total24
        success     = $success24
        failed      = $failed24
        successRate = $successRate
        avgDuration = $avgDuration
        longestRun  = $longestRun
    }
    trend           = $trend
    mostRun         = $mostRun
    mostFailing     = $mostFailing
    slowest         = $slowest
    recentFailures  = $recentFailures
    stepTypeStats   = $stepTypeStats
}
