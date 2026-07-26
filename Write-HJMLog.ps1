# Write-HJMLog.ps1
function Write-HJMLog {
    param(
        [string]$ComputerName,
        [bool]$ADReady,
        [bool]$EntraReady,
        [bool]$DeltaTriggered,
        [string]$EntraStatus = "Unknown",
        [int]$EntraMatchCount = 0,
        [string]$Reason = "None",
        [string]$ErrorMessage = ""
    )

    $logFile = Join-Path -Path $PSScriptRoot -ChildPath "HybridJoin.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $cleanError = $ErrorMessage -replace "\r|\n", " "
    $cleanError = $cleanError -replace "\|", "/"

    $entry = "$timestamp | $ComputerName | ADReady=$ADReady | EntraReady=$EntraReady | DeltaTriggered=$DeltaTriggered | EntraStatus=$EntraStatus | EntraMatchCount=$EntraMatchCount | Reason=$Reason"
    if (-not [string]::IsNullOrWhiteSpace($cleanError)) {
        $entry = "$entry | Error=$cleanError"
    }

    Add-Content -Path $logFile -Value $entry
}
