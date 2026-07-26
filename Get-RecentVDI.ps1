# Get-RecentVDI.ps1
function Get-RecentVDI {
    param(
        [string[]]$SearchBases,
        [int]$RecentMinutes = 20
    )

    $cutoffUtc = (Get-Date).ToUniversalTime().AddMinutes(-1 * $RecentMinutes)
    $cutoffLdap = $cutoffUtc.ToString("yyyyMMddHHmmss.0Z")
    $queryParams = @{
        LDAPFilter = "(whenCreated>=$cutoffLdap)"
        Properties = "whenCreated"
    }
    $computers = @()
    $validSearchBases = @()
    $invalidSearchBases = @()

    if ($SearchBases -and $SearchBases.Count -gt 0) {
        foreach ($base in $SearchBases) {
            if ([string]::IsNullOrWhiteSpace($base)) {
                continue
            }

            $normalizedBase = $base.Trim()

            try {
                $adObject = Get-ADObject -Identity $normalizedBase -ErrorAction Stop
                $validSearchBases += $adObject.DistinguishedName
            }
            catch {
                $invalidSearchBases += [pscustomobject]@{
                    SearchBase = $normalizedBase
                    Error      = $_.Exception.Message
                }
            }
        }

        foreach ($validBase in $validSearchBases) {
            try {
                $computers += @(Get-ADComputer @queryParams -SearchBase $validBase -ErrorAction Stop)
            }
            catch {
                $invalidSearchBases += [pscustomobject]@{
                    SearchBase = $validBase
                    Error      = $_.Exception.Message
                }
            }
        }
    }
    else {
        $computers = @(Get-ADComputer @queryParams)
    }

    $uniqueComputers = @($computers | Sort-Object DistinguishedName -Unique)

    return [pscustomobject]@{
        Computers          = $uniqueComputers
        ValidSearchBases   = @($validSearchBases | Sort-Object -Unique)
        InvalidSearchBases = @($invalidSearchBases)
        CutoffUtc          = $cutoffUtc
    }
}
