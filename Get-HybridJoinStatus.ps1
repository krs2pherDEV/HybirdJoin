# Get-HybridJoinStatus.ps1
function Get-HybridJoinStatus {
    param(
        [string]$ComputerName
    )

    $obj = Get-ADComputer $ComputerName -Properties userCertificate, 'msDS-KeyCredentialLink'

    # Guard against property being absent entirely (not just empty)
    $hasUserCert = $obj.userCertificate -and @($obj.userCertificate).Count -gt 0

    $keyCredProp = $obj.PSObject.Properties['msDS-KeyCredentialLink']
    $hasKeyCredential = $keyCredProp -and $keyCredProp.Value -and @($keyCredProp.Value).Count -gt 0

    return ($hasUserCert -and $hasKeyCredential)
}
