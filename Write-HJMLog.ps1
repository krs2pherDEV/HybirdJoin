# Write-HJMLog.ps1
function Write-HJMLog {
    param(
        [string]$ComputerName,
        [bool]$ADReady,
        [bool]$EntraReady,
        [bool]$DeltaTriggered,
        [string]$EntraStatus = "Unknown",
        [int]$EntraMatchCount = 0,
        [string]$EntraMatchType = "None",
        [string]$Reason = "None",
        [string]$ErrorMessage = ""
    )

    # Use configured log path if set; fall back to script directory
    $logFile = if ($HybridJoinConfig -and
                   $HybridJoinConfig.ContainsKey('LogPath') -and
                   -not [string]::IsNullOrWhiteSpace($HybridJoinConfig.LogPath)) {
        $HybridJoinConfig.LogPath
    } else {
        Join-Path -Path $PSScriptRoot -ChildPath 'HybridJoin.log'
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $cleanError = $ErrorMessage -replace "\r|\n", " "
    $cleanError = $cleanError -replace "\|", "/"

    $entry = "$timestamp | $ComputerName | ADReady=$ADReady | EntraReady=$EntraReady | DeltaTriggered=$DeltaTriggered | EntraStatus=$EntraStatus | EntraMatchCount=$EntraMatchCount | EntraMatchType=$EntraMatchType | Reason=$Reason"
    if (-not [string]::IsNullOrWhiteSpace($cleanError)) {
        $entry = "$entry | Error=$cleanError"
    }

    Add-Content -Path $logFile -Value $entry
}
