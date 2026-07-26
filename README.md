# Hybrid Join Monitor for Omnissa Horizon Instant Clones

## Executive Summary

This solution accelerates Microsoft Entra hybrid join readiness for Omnissa
Horizon Instant Clone desktops by detecting newly created AD computer objects and
triggering throttled Entra Connect delta sync when needed.

What problem it solves:
- Default Entra Connect cadence (commonly 30 minutes) can delay hybrid join and
  downstream SSO readiness for OneDrive and Outlook.
- Non-persistent Instant Clone workflows can expose users to this delay,
  especially during image updates and burst provisioning.

What this implementation does:
- Monitors recent VDI computer objects in scoped OUs.
- Verifies AD-side hybrid join readiness and Entra visibility.
- Triggers delta sync only when criteria are met and throttle permits.
- Logs structured outcomes for operations and architecture reporting.

Recommended operating model:
- Keep a warm pool (start with 2 spare desktops, then tune).
- Run monitor every 2 minutes.
- Keep delta sync throttle at 10 minutes initially.
- Treat "device in Entra" and "AzureAdPrt=YES" as separate readiness checks.

Expected outcome:
- Typical readiness reduction from long sync-window behavior to a much shorter
  operational window, with most benefit during pool changes and user bursts.
- Better auditability and faster root-cause analysis through structured logging.

Architecture caveat:
- Reusing computer accounts helps steady-state performance but does not eliminate
  all sync dependencies during recompose/rebuild events. Maintain OU scoping,
  stale object cleanup, and warm-capacity practices.

## Overview

This folder contains PowerShell scripts to monitor newly created VDI computer objects, check hybrid-join readiness, check Entra device visibility, and optionally trigger an Entra Connect delta sync.

Primary goal:
- Reduce time between VDI creation and hybrid join readiness for user workloads such as OneDrive and Outlook.

Context:
- Designed for Omnissa Horizon non-persistent Instant Clone pools.
- Assumes Instant Clone provisioning (not Sysprep-based imaging workflows).
- Supports environments where VDI names may be reused.

## How It Works

High-level flow in `HybridJoinMonitor.ps1`:
1. Load configuration from `HybridJoinConfig.ps1`.
2. Find recent VDI computer objects from AD (`Get-RecentVDI.ps1`).
3. Check AD hybrid-join attributes (`Get-HybridJoinStatus.ps1`).
4. Check Entra device visibility (`Get-EntraDeviceStatus.ps1`).
5. If AD is ready but Entra is not found, attempt a throttled delta sync (`Invoke-DeltaSync.ps1`).
6. Write structured logs (`Write-HJMLog.ps1`).

## Files

- `HybridJoinMonitor.ps1` : Main controller.
- `HybridJoinConfig.ps1` : Customer-editable configuration.
- `Get-RecentVDI.ps1` : Finds recently created AD computer objects.
- `Get-HybridJoinStatus.ps1` : Checks AD attributes indicating hybrid-join readiness.
- `Get-EntraDeviceStatus.ps1` : Checks for Entra device presence and query errors.
- `Invoke-DeltaSync.ps1` : Throttled trigger for Entra Connect delta sync.
- `Write-HJMLog.ps1` : Appends structured records to log file.
- `Setup-HybridJoinMonitor.ps1` : One-time interactive setup for config and scheduled task.
- `Setup-HybridJoinMonitor.log` : Setup run log with preflight checks, summary values, and actions.
- `LastSync.txt` : Marker file for delta sync throttling.
- `HybridJoin.log` : Operational log output.

## Deployment Location (Recommended)

Recommended deployment location:
Run this solution on the Microsoft Entra Connect (Azure AD Connect) server.

Why:
- `Start-ADSyncSyncCycle` runs where the ADSync module is installed.
- Running locally avoids remote PowerShell/delegation complexity.
- This is the simplest and most supportable operating model for customer rollout.

## Prerequisites

Run context should have:
- Active Directory module available.
- Microsoft Graph PowerShell module available.
- Permissions to query AD computer objects and OUs.
- Permissions to query Entra devices.
- Permission to run `Start-ADSyncSyncCycle` on the Entra Connect server.

Required commands verified at startup:
- `Get-ADComputer`
- `Get-ADObject`
- `Get-MgDevice`
- `Start-ADSyncSyncCycle`

Recommended:
- Run from a dedicated automation account or scheduled task service account.
- Ensure system time is accurate and outbound connectivity to Microsoft identity endpoints is healthy.

## Configuration

Edit `HybridJoinConfig.ps1`.

### Settings

- `RecentMinutes`
  - Number of minutes to look back for newly created AD computer objects.
  - Default: `20`

- `DeltaSyncMinIntervalMinutes`
  - Minimum minutes between sync trigger attempts.
  - Default: `10`

- `VdiSearchBases`
  - List of AD OU distinguished names to scope discovery.
  - If empty, search is not OU-scoped.
  - Invalid entries are logged as config errors.

### Distinguished Name Examples

Use full DN format:

```text
OU=HorizonVDI,OU=Desktops,DC=contoso,DC=com
OU=InstantClones,OU=VDI,DC=contoso,DC=com
```

Example config:

```powershell
$HybridJoinConfig = @{
    RecentMinutes = 20
    DeltaSyncMinIntervalMinutes = 10
    VdiSearchBases = @(
        "OU=HorizonVDI,OU=Desktops,DC=contoso,DC=com",
        "OU=InstantClones,OU=VDI,DC=contoso,DC=com"
    )
}
```

## Setup and Usage

## One-Time Setup (Recommended)

Use the setup helper to configure OU scope, timing values, and scheduled task in
one run.

1. Open PowerShell as Administrator.
2. Run this on the Entra Connect server.
3. Run:

```powershell
Set-Location C:\Scripts\HybridJoin
.\Setup-HybridJoinMonitor.ps1
```

Optional preview mode (no changes applied):

```powershell
Set-Location C:\Scripts\HybridJoin
.\Setup-HybridJoinMonitor.ps1 -DryRun
```

The setup script prompts for:
- `RecentMinutes`
- `DeltaSyncMinIntervalMinutes`
- VDI OU distinguished names (semicolon-separated)
- Scheduled task name and interval
- Run-as account (LocalSystem or service account)

Output:
- Updates `HybridJoinConfig.ps1`
- Creates or updates the scheduled task that runs `HybridJoinMonitor.ps1`
- Ensures `LastSync.txt` exists
- Validates required commands exist: `Get-ADComputer`, `Get-ADObject`, `Get-MgDevice`, `Start-ADSyncSyncCycle`
- In `-DryRun` mode, shows planned actions without writing files or changing tasks
- Writes setup execution details to `Setup-HybridJoinMonitor.log`

After setup, run one manual execution and review `HybridJoin.log`.

### First Manual Validation

1. Authenticate Graph (if needed in your run context):

```powershell
Connect-MgGraph -Scopes Device.Read.All
```

2. Run monitor once:

```powershell
Set-Location C:\Scripts\HybridJoin
.\HybridJoinMonitor.ps1
```

3. Review log output:

```powershell
Get-Content .\HybridJoin.log -Tail 100
```

## Log Format

Each entry is pipe-delimited:

```text
yyyy-MM-dd HH:mm:ss | ComputerName | ADReady=<bool> | EntraReady=<bool> | DeltaTriggered=<bool> | EntraStatus=<status> | EntraMatchCount=<int> | Reason=<reason> | Error=<optional>
```

### Common Reason Values

- `RunStart` : Run started with config summary.
- `InvalidSearchBase` : OU DN is invalid or inaccessible.
- `MissingCommand` : Required command not available.
- `ADNotReady` : AD attributes not yet ready.
- `AlreadyInEntra` : Device is already present in Entra.
- `DeltaSyncTriggered` : Delta sync started.
- `DeltaSyncSuppressedOrFailed` : Sync held by throttle or sync call failed.
- `EntraQueryError` : Entra query failed.
- `MachineProcessingError` : Unhandled machine-level error.

### Common EntraStatus Values

- `Found`
- `NotFound`
- `QueryError`
- `ConfigInfo`
- `ConfigError`
- `ProcessingError`

## Best Practices for VDI Hybrid Join

- Use clone-type-specific naming guidance:
  - Full clone pools: Follow current Omnissa guidance for your version. Reusing existing computer accounts is commonly recommended to avoid orphaned AD objects when pools are rebuilt.
  - Omnissa Horizon Instant Clone pools (non-persistent): Reuse can work well, but object lifecycle hygiene is critical. Keep stale AD and Entra device objects cleaned up and monitor for duplicate/old records.
- If unique naming is operationally possible, it reduces Entra object collision risk. If reuse is required, keep cleanup and monitoring in place.
- Keep OU scoping tight to reduce AD query load and improve consistency.
- Keep sync interval conservative to avoid over-driving Entra Connect.
- Treat hybrid join and Azure PRT as related but separate validation tracks.

## Troubleshooting

### No machines found

- Increase `RecentMinutes` temporarily.
- Verify VDI objects are created in configured OUs.
- Confirm OU DN syntax and accessibility.

### Frequent `EntraQueryError`

- Validate Graph authentication/token in run context.
- Verify permissions and module version.
- Check network/proxy/TLS path to Microsoft endpoints.

### `DeltaSyncSuppressedOrFailed` appears often

- Confirm whether suppression is expected due to `DeltaSyncMinIntervalMinutes`.
- Validate `Start-ADSyncSyncCycle` permission and Entra Connect health.

### Hybrid join appears complete but no Azure PRT

- Investigate user token broker/WAM and profile persistence behavior.
- Validate time sync, identity endpoints, and Conditional Access flow.

## Suggested Customer Test Plan

1. Configure OU search bases and baseline timing values.
2. Run script manually and confirm `RunStart` plus no config errors.
3. Recompose a small pilot pool.
4. Track transition timing from AD object creation to `AlreadyInEntra`.
5. Compare against prior baseline and adjust interval/window only as needed.

## Validation Checklist

### 1) Server and Execution Context

1. Confirm testing is being performed on the recommended host (Microsoft Entra
  Connect server).
2. Open PowerShell as Administrator.
3. Confirm script files are present in this folder.

### 2) Dry Run Setup (No Changes)

1. Run:

```powershell
Set-Location C:\Scripts\HybridJoin
.\Setup-HybridJoinMonitor.ps1 -DryRun
```

2. Confirm output shows:
  - Required command checks passed
  - OU DN validation results
  - Planned config and scheduled task actions
3. Review `Setup-HybridJoinMonitor.log`.

### 3) Real Setup Run

1. Run:

```powershell
Set-Location C:\Scripts\HybridJoin
.\Setup-HybridJoinMonitor.ps1
```

2. Confirm:
  - `HybridJoinConfig.ps1` updated with expected values
  - Scheduled task created or updated
  - `Setup-HybridJoinMonitor.log` contains completion entry

### 4) Manual Monitor Execution Test

1. Authenticate Graph in the same run context if required.
2. Run:

```powershell
.\HybridJoinMonitor.ps1
```

3. Confirm new records are written to `HybridJoin.log`.

### 5) Functional Log Validation

1. Confirm startup/config record exists:
  - `Reason=RunStart`
2. Confirm no blocking setup/config errors:
  - No `Reason=MissingCommand`
  - No `Reason=InvalidSearchBase` (unless intentionally overridden)
3. For candidate desktops, confirm reasonable state progression:
  - `ADNotReady` (early lifecycle)
  - `DeltaSyncTriggered` or `DeltaSyncSuppressedOrFailed`
  - `AlreadyInEntra`

### 6) Scheduled Task Validation

1. Confirm task interval is as expected (recommended baseline: 2 minutes).
2. Confirm task runs under intended account.
3. Confirm `HybridJoin.log` continues receiving new records on schedule.

### 7) Pilot Pool Validation

1. Recompose a small pilot pool.
2. Measure:
  - AD computer object creation to first `Reason=AlreadyInEntra`
  - First user logon to `AzureAdPrt : YES`
3. Compare with pre-change baseline.

### 8) Example Acceptance Criteria

1. Setup preflight completes with no blocking errors.
2. Hybrid join readiness improves materially from baseline.
3. No sustained scheduled task failures over 24 hours.
4. Operations runbook is clear and repeatable.

## Architecture and Operations Strategy

### 1) Avoid Pure Just-in-Time Provisioning

For Omnissa Horizon Instant Clones, "create on user request" with zero warm
capacity often exposes users to hybrid-join and PRT timing windows.

Recommended:
- Maintain a small warm pool of pre-created desktops (start with 2, then tune).
- After image publish/recompose, pre-provision desktops and wait for join/PRT
  readiness before broad user access.

### 2) Account Reuse Reduces, But Does Not Eliminate, Sync Dependency

Reusing computer accounts helps steady-state behavior, but some lifecycle events
still require Entra Connect propagation before full readiness:
- New pool creation
- Snapshot push/recompose waves
- Stale object cleanup/rebuild events
- Any pending or "device not found" registration state

Operationally, keep monitor + throttled delta sync as a safety net.

### 3) Recommended Scheduling Baseline

Start with:
- Scheduled task interval: every 2 minutes
- Delta sync minimum interval: 10 minutes
- Recent discovery window: 20 minutes

Tune based on observed behavior:
- If user bursts still see long delay, reduce delta minimum interval to 5 minutes
  for pilot testing and monitor Entra Connect load.
- If sync server pressure rises, increase interval and rely more on warm capacity.

### 4) Separate Two Success Conditions

Track separately:
- Device readiness: hybrid join completed and present in Entra
- User readiness: `AzureAdPrt : YES` for user logon SSO

This prevents conflating device registration delay with token acquisition issues.

### 5) Metrics to Share with Architecture Team

Capture these timings per desktop:
- AD computer object creation time
- First log entry showing `ADReady=True`
- First log entry showing `Reason=AlreadyInEntra`
- First successful user `dsregcmd /status` showing `AzureAdPrt : YES`

Report median and p95 values before and after implementation.

### 6) Runbook Recommendations

- Validate OU scope in Entra Connect includes VDI computer OUs.
- Maintain stale AD and Entra object cleanup process for clone lifecycle.
- Keep a documented recompose workflow:
  1. Publish image/snapshot
  2. Pre-provision warm desktops
  3. Allow sync/join to settle
  4. Open user access
- Review `HybridJoin.log` for `ConfigError`, `InvalidSearchBase`, and
  `EntraQueryError` after each major pool change.

## Safety Notes

- Script triggers Entra Connect delta sync only when criteria are met and interval allows it.
- Log file and sync marker file are script-folder relative.
- Keep this folder secured since logs may include environment details.
