# Save or update a schedule to nexus-config/schedules/
param(
    [Parameter(Mandatory)] [string]$ScheduleJson
)

try {
    $schedule = $ScheduleJson | ConvertFrom-Json

    # Handle toggle-only updates
    if ($null -ne $schedule.toggleEnabled) {
        $existingContent = Read-Blob -Container 'nexus-config' -BlobPath "schedules/$($schedule.name).json"
        if ($existingContent) {
            $existing = $existingContent | ConvertFrom-Json
            $existing.enabled = [bool]$schedule.toggleEnabled
            $json = $existing | ConvertTo-Json -Depth 10
            Write-Blob -Container 'nexus-config' -BlobPath "schedules/$($existing.name).json" -Content $json
            return @{ success = $true; message = "Schedule '$($existing.name)' updated" }
        }
        return @{ success = $false; message = "Schedule not found"; statusCode = 404 }
    }

    if ([string]::IsNullOrWhiteSpace($schedule.name) -or [string]::IsNullOrWhiteSpace($schedule.workflow)) {
        return @{ success = $false; message = "Schedule name and workflow are required"; statusCode = 400 }
    }

    $scheduleObj = @{
        name     = $schedule.name
        workflow = $schedule.workflow
        interval = $schedule.interval
        nextRun  = $schedule.nextRun
        enabled  = [bool]$schedule.enabled
    }

    $json = $scheduleObj | ConvertTo-Json -Depth 10
    Write-Blob -Container 'nexus-config' -BlobPath "schedules/$($schedule.name).json" -Content $json

    return @{ success = $true; message = "Schedule '$($schedule.name)' saved" }
} catch {
    return @{ success = $false; message = "Error saving schedule: $($_.Exception.Message)"; statusCode = 500 }
}
