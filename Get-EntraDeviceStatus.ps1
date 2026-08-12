# Get-EntraDeviceStatus.ps1
function Get-EntraDeviceStatus {
    param(
        [string]$ComputerName,
        [string]$DeviceId
    )

    try {
        if (-not [string]::IsNullOrWhiteSpace($DeviceId)) {
            $devices = @(Get-MgDevice -Filter "deviceId eq '$DeviceId'")
            $matchType = "DeviceId"
        }
        else {
            $escapedComputerName = $ComputerName -replace "'", "''"
            $devices = @(Get-MgDevice -Filter "displayName eq '$escapedComputerName'")
            $matchType = "DisplayName"
        }

        if ($devices.Count -gt 0) {
            return [pscustomobject]@{
                Status     = "Found"
                IsPresent  = $true
                MatchCount = $devices.Count
                MatchType  = $matchType
                Error      = $null
            }
        }

        return [pscustomobject]@{
            Status     = "NotFound"
            IsPresent  = $false
            MatchCount = 0
            MatchType  = $matchType
            Error      = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Status     = "QueryError"
            IsPresent  = $false
            MatchCount = 0
            MatchType  = "None"
            Error      = $_.Exception.Message
        }
    }
}
