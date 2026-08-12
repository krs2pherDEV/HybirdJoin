# Get-HybridJoinStatus.ps1
function Get-HybridJoinInfo {
    param(
        [string]$ComputerName,
        [object]$ADComputer
    )

    $computer = if ($ADComputer) {
        $ADComputer
    }
    else {
        Get-ADComputer $ComputerName -Properties userCertificate, ObjectGUID
    }

    $certificateValue = $computer.userCertificate
    $certificates = @()
    if ($certificateValue -is [byte[]]) {
        $certificates = @(, $certificateValue)
    }
    elseif ($certificateValue) {
        $certificates = @($certificateValue | Where-Object { $_ -is [byte[]] })
    }

    $certificateDetails = foreach ($rawCertificate in $certificates) {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $fingerprint = [System.BitConverter]::ToString($sha256.ComputeHash($rawCertificate)).Replace("-", "")
        }
        finally {
            $sha256.Dispose()
        }

        try {
            $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 `
                -ArgumentList (, $rawCertificate) `
                -ErrorAction Stop
            $deviceId = $null
            $commonName = $certificate.GetNameInfo(
                [System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName,
                $false
            )
            $parsedDeviceId = [guid]::Empty
            if ([guid]::TryParse($commonName, [ref]$parsedDeviceId)) {
                $deviceId = $parsedDeviceId.ToString()
            }

            [pscustomobject]@{
                Fingerprint = $fingerprint
                DeviceId    = $deviceId
                NotBefore   = $certificate.NotBefore
            }
        }
        catch {
            [pscustomobject]@{
                Fingerprint = $fingerprint
                DeviceId    = $null
                NotBefore   = [datetime]::MinValue
            }
        }
    }

    $currentCertificate = $certificateDetails |
        Sort-Object NotBefore -Descending |
        Select-Object -First 1

    return [pscustomobject]@{
        IsReady                = ($certificateDetails.Count -gt 0)
        CertificateFingerprint = (($certificateDetails.Fingerprint | Sort-Object) -join ";")
        DeviceId               = $currentCertificate.DeviceId
        Computer               = $computer
    }
}

function Get-HybridJoinStatus {
    param(
        [string]$ComputerName
    )

    $joinInfo = Get-HybridJoinInfo -ComputerName $ComputerName
    return [bool]$joinInfo.IsReady
}
