# Get-EntraDeviceStatus.ps1
function Get-EntraDeviceStatus {
    param(
        [string]$ComputerName
    )

    try {
        $escapedComputerName = $ComputerName -replace "'", "''"
        $devices = @(Get-MgDevice -Filter "displayName eq '$escapedComputerName'")

        if ($devices.Count -gt 0) {
            return [pscustomobject]@{
                Status     = "Found"
                IsPresent  = $true
                MatchCount = $devices.Count
                Error      = $null
            }
        }

        return [pscustomobject]@{
            Status     = "NotFound"
            IsPresent  = $false
            MatchCount = 0
            Error      = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Status     = "QueryError"
            IsPresent  = $false
            MatchCount = 0
            Error      = $_.Exception.Message
        }
    }
}
