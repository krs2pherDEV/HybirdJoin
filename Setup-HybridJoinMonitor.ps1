# Setup-HybridJoinMonitor.ps1
# One-time setup helper for HybridJoinMonitor.

[CmdletBinding()]
param(
    [switch]$DryRun
)

function Read-DefaultString {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [string]$DefaultValue = ""
    )

    if ([string]::IsNullOrWhiteSpace($DefaultValue)) {
        $value = Read-Host $Prompt
    }
    else {
        $value = Read-Host "$Prompt [$DefaultValue]"
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        return $DefaultValue
    }

    return $value.Trim()
}

function Read-DefaultInt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [Parameter(Mandatory = $true)]
        [int]$DefaultValue,
        [int]$Minimum = 1,
        [int]$Maximum = 10080
    )

    while ($true) {
        $value = Read-Host "$Prompt [$DefaultValue]"
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $DefaultValue
        }

        $parsed = 0
        if ([int]::TryParse($value, [ref]$parsed) -and $parsed -ge $Minimum -and $parsed -le $Maximum) {
            return $parsed
        }

        Write-Host "Enter a number between $Minimum and $Maximum." -ForegroundColor Yellow
    }
}

function Read-YesNo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [bool]$DefaultYes = $true
    )

    $defaultHint = if ($DefaultYes) { "Y/n" } else { "y/N" }

    while ($true) {
        $value = Read-Host "$Prompt [$defaultHint]"
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $DefaultYes
        }

        switch ($value.Trim().ToLowerInvariant()) {
            "y" { return $true }
            "yes" { return $true }
            "n" { return $false }
            "no" { return $false }
            default { Write-Host "Enter Y or N." -ForegroundColor Yellow }
        }
    }
}

function Write-SetupLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $script:setupLogFile -Value "$timestamp | $Message" -Encoding ASCII
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script in an elevated PowerShell session (Run as Administrator)."
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$configFile = Join-Path -Path $scriptRoot -ChildPath "HybridJoinConfig.ps1"
$monitorScript = Join-Path -Path $scriptRoot -ChildPath "HybridJoinMonitor.ps1"
$lastSyncFile = Join-Path -Path $scriptRoot -ChildPath "LastSync.txt"
$script:setupLogFile = Join-Path -Path $scriptRoot -ChildPath "Setup-HybridJoinMonitor.log"

Write-SetupLog "Setup started. DryRun=$DryRun"

if (-not (Test-Path $monitorScript)) {
    Write-SetupLog "ERROR: Cannot find HybridJoinMonitor.ps1 in $scriptRoot"
    throw "Cannot find HybridJoinMonitor.ps1 in $scriptRoot"
}

$requiredCommands = @(
    "Get-ADComputer",
    "Get-ADObject",
    "Get-MgDevice",
    "Start-ADSyncSyncCycle"
)

$missingCommands = @()
foreach ($commandName in $requiredCommands) {
    if (-not (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
        $missingCommands += $commandName
    }
}

if ($missingCommands.Count -gt 0) {
    $missingList = $missingCommands -join ", "
    Write-SetupLog "ERROR: Missing required command(s): $missingList"
    throw "Missing required command(s): $missingList. Install/import required modules and re-run setup."
}

Write-SetupLog "Prerequisite command check passed."

Write-Host "Hybrid Join Monitor setup" -ForegroundColor Cyan
Write-Host "This will update HybridJoinConfig.ps1 and create/update a scheduled task." -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "DRY RUN mode enabled: no files or scheduled tasks will be changed." -ForegroundColor Yellow
    Write-SetupLog "Dry run mode enabled."
}
Write-Host ""

$recentMinutes = Read-DefaultInt -Prompt "RecentMinutes (lookback window)" -DefaultValue 20 -Minimum 1 -Maximum 240
$deltaMinutes = Read-DefaultInt -Prompt "DeltaSyncMinIntervalMinutes" -DefaultValue 10 -Minimum 1 -Maximum 240

$ouPrompt = "Enter VDI OU distinguished names separated by semicolon (or leave blank for all OUs)"
$ouInput = Read-DefaultString -Prompt $ouPrompt -DefaultValue ""
$searchBases = @()
if (-not [string]::IsNullOrWhiteSpace($ouInput)) {
    $searchBases = @(
        $ouInput.Split(";", [System.StringSplitOptions]::RemoveEmptyEntries) |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    $searchBases = @($searchBases | Sort-Object -Unique)
}

if ($searchBases.Count -gt 0) {
    $adObjectCommand = Get-Command -Name "Get-ADObject" -ErrorAction SilentlyContinue
    if ($adObjectCommand) {
        $invalidBases = @()
        foreach ($base in $searchBases) {
            try {
                $adObject = Get-ADObject -Identity $base -ErrorAction Stop
                if (-not $adObject) {
                    $invalidBases += [pscustomobject]@{ SearchBase = $base; Error = "No object returned." }
                }
            }
            catch {
                $invalidBases += [pscustomobject]@{ SearchBase = $base; Error = $_.Exception.Message }
            }
        }

        if ($invalidBases.Count -gt 0) {
            Write-Host "The following OU distinguished names could not be validated:" -ForegroundColor Yellow
            foreach ($invalid in $invalidBases) {
                Write-Host " - $($invalid.SearchBase) :: $($invalid.Error)" -ForegroundColor Yellow
                Write-SetupLog "DN validation warning: $($invalid.SearchBase) :: $($invalid.Error)"
            }

            $continueWithInvalid = Read-YesNo -Prompt "Continue setup with these DN values anyway" -DefaultYes $false
            if (-not $continueWithInvalid) {
                Write-SetupLog "ERROR: Setup cancelled by operator due to invalid OU distinguished names."
                throw "Setup cancelled due to invalid OU distinguished names."
            }
        }
    }
    else {
        Write-Host "Get-ADObject was not found. DN validation was skipped." -ForegroundColor Yellow
        Write-SetupLog "DN validation skipped because Get-ADObject was not found."
    }
}

if ($searchBases.Count -gt 0) {
    Write-SetupLog "Configured VDI OUs: $($searchBases -join '; ')"
}
else {
    Write-SetupLog "Configured VDI OUs: <all computer objects>"
}

$baseLines = @()
if ($searchBases.Count -gt 0) {
    foreach ($base in $searchBases) {
        $escaped = $base.Replace('"', '""')
        $baseLines += ('        "{0}"' -f $escaped)
    }
}
else {
    $baseLines += '        # "OU=InstantClones,OU=VDI,DC=contoso,DC=com"'
}

$configContent = @(
    "# HybridJoinConfig.ps1",
    "# Configure customer-specific settings here.",
    "#",
    "# Use distinguished names (DN) for AD OU paths, for example:",
    "#   OU=HorizonVDI,OU=Desktops,DC=contoso,DC=com",
    "#   OU=InstantClones,OU=VDI,DC=contoso,DC=com",
    "#",
    "# Leave empty to search across all synced computer objects.",
    "$" + "HybridJoinConfig = @{",
    "    # Time window to consider newly created VDI computer objects. Older objects",
    "    # are also processed when their userCertificate fingerprint changes.",
    "    RecentMinutes = $recentMinutes",
    "",
    "    # Minimum wait time between AAD Connect delta sync cycles.",
    "    DeltaSyncMinIntervalMinutes = $deltaMinutes",
    "",
    "    VdiSearchBases = @(",
    ($baseLines -join ",`r`n"),
    "    )",
    "",
    "    # Leave empty to write HybridJoin.log to the script directory.",
    '    LogPath = ""',
    "",
    "    # Leave empty to write HybridJoinState.json to the script directory.",
    '    StatePath = ""',
    "}"
) -join "`r`n"

if ($DryRun) {
    Write-Host "[DRYRUN] Would update: $configFile" -ForegroundColor Yellow
    Write-SetupLog "DRYRUN: Would update config file at $configFile"
}
else {
    Set-Content -Path $configFile -Value $configContent -Encoding ASCII
    Write-Host "Updated HybridJoinConfig.ps1" -ForegroundColor Green
    Write-SetupLog "Updated config file at $configFile"
}

if (-not (Test-Path $lastSyncFile)) {
    if ($DryRun) {
        Write-Host "[DRYRUN] Would create: $lastSyncFile" -ForegroundColor Yellow
        Write-SetupLog "DRYRUN: Would create marker file at $lastSyncFile"
    }
    else {
        Set-Content -Path $lastSyncFile -Value "" -Encoding ASCII
        Write-SetupLog "Created marker file at $lastSyncFile"
    }
}

$taskName = Read-DefaultString -Prompt "Scheduled task name" -DefaultValue "HybridJoinMonitor"
$taskIntervalMinutes = Read-DefaultInt -Prompt "Task run interval (minutes)" -DefaultValue 2 -Minimum 1 -Maximum 60
$taskStartDelayMinutes = Read-DefaultInt -Prompt "Start delay from now (minutes)" -DefaultValue 1 -Minimum 0 -Maximum 60
$runAsSystem = Read-YesNo -Prompt "Run task as LocalSystem account" -DefaultYes $false

Write-Host ""
Write-Host "Configuration Summary:" -ForegroundColor Cyan
Write-Host "  RecentMinutes: $recentMinutes"
Write-Host "  DeltaSyncMinIntervalMinutes: $deltaMinutes"
if ($searchBases.Count -gt 0) {
    Write-Host "  VDI OUs:"
    foreach ($base in $searchBases) {
        Write-Host "    - $base"
    }
}
else {
    Write-Host "  VDI OUs: <all computer objects>"
}
Write-Host "  Scheduled Task: $taskName (every $taskIntervalMinutes minutes)"
Write-Host "  Start Delay: $taskStartDelayMinutes minute(s)"
Write-Host "  Run As: $(if ($runAsSystem) { 'LocalSystem' } else { 'Service account' })"
Write-SetupLog "Summary: RecentMinutes=$recentMinutes; DeltaSyncMinIntervalMinutes=$deltaMinutes; TaskName=$taskName; TaskIntervalMinutes=$taskIntervalMinutes; StartDelayMinutes=$taskStartDelayMinutes; RunAs=$(if ($runAsSystem) { 'LocalSystem' } else { 'ServiceAccount' })"

$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    $replace = Read-YesNo -Prompt "Task '$taskName' already exists. Replace it" -DefaultYes $true
    if (-not $replace) {
        Write-SetupLog "ERROR: Setup cancelled by operator because existing task was not replaced."
        throw "Setup cancelled. Existing task was not modified."
    }

    if ($DryRun) {
        Write-Host "[DRYRUN] Would remove existing scheduled task: $taskName" -ForegroundColor Yellow
        Write-SetupLog "DRYRUN: Would remove existing scheduled task '$taskName'"
    }
    else {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-SetupLog "Removed existing scheduled task '$taskName'"
    }
}

$powerShellExe = Join-Path -Path $env:WINDIR -ChildPath "System32\WindowsPowerShell\v1.0\powershell.exe"
$actionArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$monitorScript`""
$action = New-ScheduledTaskAction -Execute $powerShellExe -Argument $actionArgs
$startTime = (Get-Date).AddMinutes($taskStartDelayMinutes)
$trigger = New-ScheduledTaskTrigger -Once -At $startTime -RepetitionInterval (New-TimeSpan -Minutes $taskIntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

if ($runAsSystem) {
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    if ($DryRun) {
        Write-Host "[DRYRUN] Would create/update scheduled task '$taskName' as LocalSystem." -ForegroundColor Yellow
        Write-SetupLog "DRYRUN: Would create/update scheduled task '$taskName' as LocalSystem"
    }
    else {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $taskPrincipal -Force | Out-Null
        Write-Host "Scheduled task '$taskName' created as LocalSystem." -ForegroundColor Green
        Write-SetupLog "Created/updated scheduled task '$taskName' as LocalSystem"
    }
}
else {
    $runAsUser = Read-DefaultString -Prompt "Run-as account (domain\\user or UPN)" -DefaultValue ""
    if ([string]::IsNullOrWhiteSpace($runAsUser)) {
        Write-SetupLog "ERROR: Run-as account was empty while LocalSystem was not selected."
        throw "Run-as account is required when not using LocalSystem."
    }

    if ($DryRun) {
        Write-Host "[DRYRUN] Would create/update scheduled task '$taskName' for account '$runAsUser'." -ForegroundColor Yellow
        Write-SetupLog "DRYRUN: Would create/update scheduled task '$taskName' for account '$runAsUser'"
    }
    else {
        $securePassword = Read-Host "Run-as password" -AsSecureString
        $passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        try {
            $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordBstr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordBstr)
        }

        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -User $runAsUser -Password $plainPassword -RunLevel Highest -Force | Out-Null
        Write-Host "Scheduled task '$taskName' created for account '$runAsUser'." -ForegroundColor Green
        Write-SetupLog "Created/updated scheduled task '$taskName' for account '$runAsUser'"
    }
}

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run complete." -ForegroundColor Cyan
    Write-SetupLog "Dry run complete."
}
else {
    Write-Host "Setup complete." -ForegroundColor Cyan
    Write-SetupLog "Setup complete."
}
Write-Host "Next step: run HybridJoinMonitor.ps1 once manually and review HybridJoin.log." -ForegroundColor Cyan
Write-SetupLog "Next step advisory displayed to operator."
