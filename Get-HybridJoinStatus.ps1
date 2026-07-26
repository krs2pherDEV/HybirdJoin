# Get-HybridJoinStatus.ps1
function Get-HybridJoinStatus {
    param(
        [string]$ComputerName
    )

    $obj = Get-ADComputer $ComputerName -Properties userCertificate, 'msDS-KeyCredentialLink'

    $keyCredentialProperty = "msDS-KeyCredentialLink"
    $keyCredentialValue = $obj.PSObject.Properties[$keyCredentialProperty].Value

    if ($obj.userCertificate -and $keyCredentialValue) {
        return $true
    }
    else {
        return $false
    }
}
