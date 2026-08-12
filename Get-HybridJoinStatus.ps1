# Get-HybridJoinStatus.ps1
function Get-HybridJoinStatus {
    param(
        [string]$ComputerName
    )

    $obj = Get-ADComputer $ComputerName -Properties userCertificate

    # Guard against property being absent entirely (not just empty)
    $hasUserCert = $obj.userCertificate -and @($obj.userCertificate).Count -gt 0

    return [bool]$hasUserCert
}
