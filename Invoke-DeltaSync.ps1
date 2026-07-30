# Invoke-DeltaSync.ps1
function Invoke-DeltaSync {
    param(
        [int]$MinimumIntervalMinutes = 10
    )

    $syncFile = Join-Path -Path $PSScriptRoot -ChildPath "LastSync.txt"

    $lastSync = (Get-Date).AddHours(-1)
    if (Test-Path $syncFile) {
        $rawLastSync = (Get-Content -Path $syncFile -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($rawLastSync)) {
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse($rawLastSync, [ref]$parsed)) {
                $lastSync = $parsed
            }
        }
    }

    $now = Get-Date
    $elapsed = ($now - $lastSync).TotalMinutes

    if ($elapsed -ge $MinimumIntervalMinutes) {
        try {
            Start-ADSyncSyncCycle -PolicyType Delta
            Set-Content -Path $syncFile -Value ($now.ToString("o")) -Encoding ASCII
            return [pscustomobject]@{ Triggered = $true;  Suppressed = $false; ErrorMessage = $null }
        }
        catch {
            return [pscustomobject]@{ Triggered = $false; Suppressed = $false; ErrorMessage = $_.Exception.Message }
        }
    }
    else {
        return [pscustomobject]@{ Triggered = $false; Suppressed = $true;  ErrorMessage = $null }
    }
}
