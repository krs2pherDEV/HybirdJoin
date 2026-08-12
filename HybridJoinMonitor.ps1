# HybridJoinMonitor.ps1
# Main controller script

# Import helper scripts
$scriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path -Path $scriptRoot -ChildPath "HybridJoinConfig.ps1")
. (Join-Path -Path $scriptRoot -ChildPath "Get-RecentVDI.ps1")
. (Join-Path -Path $scriptRoot -ChildPath "Get-HybridJoinStatus.ps1")
. (Join-Path -Path $scriptRoot -ChildPath "Get-HybridJoinState.ps1")
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
try {
    $monitorState = Get-HybridJoinState
}
catch {
    Write-HJMLog -ComputerName "_CONFIG_" `
        -ADReady $false `
        -EntraReady $false `
        -DeltaTriggered $false `
        -EntraStatus "ConfigError" `
        -EntraMatchCount 0 `
        -Reason "StateReadError" `
        -ErrorMessage $_.Exception.Message
    throw
}
$certificateState = $monitorState.Certificates
$candidateResult = Get-HybridJoinCandidates `
    -RecentComputers @($recentDiscovery.Computers) `
    -CertificateComputers @($recentDiscovery.CertificateComputers) `
    -CertificateState $certificateState
$joinInfoByGuid = $candidateResult.JoinInfoByGuid
$recentVDI = @($candidateResult.Computers)
$stateChanged = $false

$startupError = "RecentMinutes=$recentMinutes; DeltaSyncMinIntervalMinutes=$deltaSyncMinIntervalMinutes; SearchBaseCount=$(@($recentDiscovery.ValidSearchBases).Count); RecentObjectCount=$(@($recentDiscovery.Computers).Count); CertificateObjectCount=$(@($recentDiscovery.CertificateComputers).Count); CandidateCount=$($recentVDI.Count)"
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
        $objectGuid = [string]$machine.ObjectGUID
        $joinInfo = if ($joinInfoByGuid.ContainsKey($objectGuid)) {
            $joinInfoByGuid[$objectGuid]
        }
        else {
            Get-HybridJoinInfo -ADComputer $machine
        }
        $adReady = $joinInfo.IsReady
        $entraResult = Get-EntraDeviceStatus -ComputerName $machine.Name -DeviceId $joinInfo.DeviceId
        $entraReady = $entraResult.IsPresent
        $deltaTriggered = $false
        $syncError = $null
        $reason = "NoAction"

        if (-not $adReady) {
            $reason = "ADNotReady"
        }
        elseif ($entraResult.Status -eq "NotFound") {
            $syncResult    = Invoke-DeltaSync -MinimumIntervalMinutes $deltaSyncMinIntervalMinutes
            $deltaTriggered = $syncResult.Triggered
            $syncError      = $syncResult.ErrorMessage
            $reason = if ($syncResult.Triggered)   { "DeltaSyncTriggered" }
                      elseif ($syncResult.Suppressed) { "DeltaSyncThrottled" }
                      else                            { "DeltaSyncFailed"   }
        }
        else {
            if ($entraResult.Status -eq "Found") {
                $reason = "AlreadyInEntra"
                if ($adReady -and -not [string]::IsNullOrWhiteSpace($joinInfo.CertificateFingerprint)) {
                    $certificateState[$objectGuid] = $joinInfo.CertificateFingerprint
                    $stateChanged = $true
                }
            }
            elseif ($entraResult.Status -eq "QueryError") {
                $reason = "EntraQueryError"
            }
        }

        $errorMessage = if (-not [string]::IsNullOrWhiteSpace($syncError)) { $syncError } else { $entraResult.Error }
        Write-HJMLog -ComputerName $machine.Name `
            -ADReady $adReady `
            -EntraReady $entraReady `
            -DeltaTriggered $deltaTriggered `
            -EntraStatus $entraResult.Status `
            -EntraMatchCount $entraResult.MatchCount `
            -EntraMatchType $entraResult.MatchType `
            -Reason $reason `
            -ErrorMessage $errorMessage
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

if ($stateChanged) {
    try {
        Save-HybridJoinState -Path $monitorState.Path -Certificates $certificateState
    }
    catch {
        Write-HJMLog -ComputerName "_CONFIG_" `
            -ADReady $false `
            -EntraReady $false `
            -DeltaTriggered $false `
            -EntraStatus "ConfigError" `
            -EntraMatchCount 0 `
            -Reason "StateWriteError" `
            -ErrorMessage $_.Exception.Message
        throw
    }
}
