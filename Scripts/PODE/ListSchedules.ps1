# List all schedules from nexus-config/schedules/
try {
    $blobs = Get-BlobList -Container 'nexus-config' -Prefix 'schedules/'
    $schedules = @()
    foreach ($blob in $blobs) {
        if ($blob.Name -notmatch '\.json$') { continue }
        $content = Read-Blob -Container 'nexus-config' -BlobPath $blob.Name
        if ($content) {
            $sch = $content | ConvertFrom-Json
            $schedules += @{
                name     = $sch.name
                workflow = $sch.workflow
                interval = $sch.interval
                nextRun  = $sch.nextRun
                enabled  = $sch.enabled
            }
        }
    }
    return @{ success = $true; schedules = $schedules }
} catch {
    return @{ success = $false; message = "Error listing schedules: $($_.Exception.Message)"; schedules = @() }
}
