# Get-HybridJoinState.ps1
function Get-HybridJoinStatePath {
    if ($HybridJoinConfig -and
        $HybridJoinConfig.ContainsKey("StatePath") -and
        -not [string]::IsNullOrWhiteSpace($HybridJoinConfig.StatePath)) {
        return $HybridJoinConfig.StatePath
    }

    return (Join-Path -Path $PSScriptRoot -ChildPath "HybridJoinState.json")
}

function Get-HybridJoinState {
    param(
        [string]$Path = (Get-HybridJoinStatePath)
    )

    $certificateState = @{}
    if (Test-Path -Path $Path) {
        try {
            $savedState = Get-Content -Path $Path -Raw | ConvertFrom-Json
            if ($savedState.Certificates) {
                foreach ($property in $savedState.Certificates.PSObject.Properties) {
                    $certificateState[$property.Name] = [string]$property.Value
                }
            }
        }
        catch {
            throw "Unable to read hybrid join state file '$Path': $($_.Exception.Message)"
        }
    }

    return [pscustomobject]@{
        Path         = $Path
        Certificates = $certificateState
    }
}

function Save-HybridJoinState {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Certificates,
        [string]$Path = (Get-HybridJoinStatePath)
    )

    $parentPath = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parentPath) -and -not (Test-Path -Path $parentPath)) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }

    $temporaryPath = "$Path.tmp"
    [pscustomobject]@{
        Version      = 1
        UpdatedUtc   = (Get-Date).ToUniversalTime().ToString("o")
        Certificates = $Certificates
    } | ConvertTo-Json -Depth 4 | Set-Content -Path $temporaryPath -Encoding UTF8

    Move-Item -Path $temporaryPath -Destination $Path -Force
}

function Get-HybridJoinCandidates {
    param(
        [object[]]$RecentComputers = @(),
        [object[]]$CertificateComputers = @(),
        [Parameter(Mandatory = $true)]
        [hashtable]$CertificateState
    )

    $candidateByGuid = @{}
    $joinInfoByGuid = @{}

    foreach ($computer in $RecentComputers) {
        $candidateByGuid[[string]$computer.ObjectGUID] = $computer
    }

    foreach ($computer in $CertificateComputers) {
        $objectGuid = [string]$computer.ObjectGUID
        $joinInfo = Get-HybridJoinInfo -ADComputer $computer
        $joinInfoByGuid[$objectGuid] = $joinInfo

        if (-not $CertificateState.ContainsKey($objectGuid) -or
            $CertificateState[$objectGuid] -ne $joinInfo.CertificateFingerprint) {
            $candidateByGuid[$objectGuid] = $computer
        }
        else {
            [void]$candidateByGuid.Remove($objectGuid)
        }
    }

    return [pscustomobject]@{
        Computers      = @($candidateByGuid.Values | Sort-Object Name)
        JoinInfoByGuid = $joinInfoByGuid
    }
}