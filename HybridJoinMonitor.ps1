# HybridJoinMonitor.ps1
# Main controller script

# Import helper scripts
$scriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path -Path $scriptRoot -ChildPath "HybridJoinConfig.ps1")
. (Join-Path -Path $scriptRoot -ChildPath "Get-RecentVDI.ps1")
. (Join-Path -Path $scriptRoot -ChildPath "Get-HybridJoinStatus.ps1")
. (Join-Path -Path $scriptRoot -ChildPath "Get-EntraDeviceStatus.ps1")
. (Join-Path -Path $scriptRoot -ChildPath "Invoke-DeltaSync.ps1")
. (Join-Path -Path $scriptRoot -ChildPath "Write-HJMLog.ps1")

$requiredCommands = @(
    "Get-ADComputer",
    "Get-ADObject",
    "Get-MgDevice",
    "Start-ADSyncSyncCycle"
)

foreach ($commandName in $requiredCommands) {
    if (-not (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
        $message = "Missing required command: $commandName"
        Write-HJMLog -ComputerName "_CONFIG_" `
            -ADReady $false `
            -EntraReady $false `
            -DeltaTriggered $false `
            -EntraStatus "ConfigError" `
            -EntraMatchCount 0 `
            -Reason "MissingCommand" `
            -ErrorMessage $message
        throw $message
    }
}

$searchBases = @()
if ($HybridJoinConfig -and $HybridJoinConfig.ContainsKey("VdiSearchBases")) {
    $searchBases = @($HybridJoinConfig.VdiSearchBases)
}

$recentMinutes = 20
if ($HybridJoinConfig -and $HybridJoinConfig.ContainsKey("RecentMinutes")) {
    if ([int]$HybridJoinConfig.RecentMinutes -gt 0) {
        $recentMinutes = [int]$HybridJoinConfig.RecentMinutes
    }
}

$deltaSyncMinIntervalMinutes = 10
if ($HybridJoinConfig -and $HybridJoinConfig.ContainsKey("DeltaSyncMinIntervalMinutes")) {
    if ([int]$HybridJoinConfig.DeltaSyncMinIntervalMinutes -gt 0) {
        $deltaSyncMinIntervalMinutes = [int]$HybridJoinConfig.DeltaSyncMinIntervalMinutes
    }
}

$recentDiscovery = Get-RecentVDI -SearchBases $searchBases -RecentMinutes $recentMinutes
$recentVDI = @($recentDiscovery.Computers)

$startupError = "RecentMinutes=$recentMinutes; DeltaSyncMinIntervalMinutes=$deltaSyncMinIntervalMinutes; SearchBaseCount=$(@($recentDiscovery.ValidSearchBases).Count); MachineCount=$($recentVDI.Count)"
Write-HJMLog -ComputerName "_CONFIG_" `
    -ADReady $true `
    -EntraReady $true `
    -DeltaTriggered $false `
    -EntraStatus "ConfigInfo" `
    -EntraMatchCount 0 `
    -Reason "RunStart" `
    -ErrorMessage $startupError

foreach ($invalidBase in @($recentDiscovery.InvalidSearchBases)) {
    Write-HJMLog -ComputerName "_CONFIG_" `
        -ADReady $false `
        -EntraReady $false `
        -DeltaTriggered $false `
        -EntraStatus "ConfigError" `
        -EntraMatchCount 0 `
        -Reason "InvalidSearchBase" `
        -ErrorMessage "$($invalidBase.SearchBase) :: $($invalidBase.Error)"
}

foreach ($machine in $recentVDI) {
    try {
        $adReady = Get-HybridJoinStatus -ComputerName $machine.Name
        $entraResult = Get-EntraDeviceStatus -ComputerName $machine.Name
        $entraReady = $entraResult.IsPresent
        $deltaTriggered = $false
        $reason = "NoAction"

        if (-not $adReady) {
            $reason = "ADNotReady"
        }
        elseif ($entraResult.Status -eq "NotFound") {
            $deltaTriggered = Invoke-DeltaSync -MinimumIntervalMinutes $deltaSyncMinIntervalMinutes
            if ($deltaTriggered) {
                $reason = "DeltaSyncTriggered"
            }
            else {
                $reason = "DeltaSyncSuppressedOrFailed"
            }
        }
        else {
            if ($entraResult.Status -eq "Found") {
                $reason = "AlreadyInEntra"
            }
            elseif ($entraResult.Status -eq "QueryError") {
                $reason = "EntraQueryError"
            }
        }

        Write-HJMLog -ComputerName $machine.Name `
            -ADReady $adReady `
            -EntraReady $entraReady `
            -DeltaTriggered $deltaTriggered `
            -EntraStatus $entraResult.Status `
            -EntraMatchCount $entraResult.MatchCount `
            -Reason $reason `
            -ErrorMessage $entraResult.Error
    }
    catch {
        Write-HJMLog -ComputerName $machine.Name `
            -ADReady $false `
            -EntraReady $false `
            -DeltaTriggered $false `
            -EntraStatus "ProcessingError" `
            -EntraMatchCount 0 `
            -Reason "MachineProcessingError" `
            -ErrorMessage $_.Exception.Message
        }
}
