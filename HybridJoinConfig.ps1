# HybridJoinConfig.ps1
# Configure customer-specific settings here.
#
# Use distinguished names (DN) for AD OU paths, for example:
#   OU=HorizonVDI,OU=Desktops,DC=contoso,DC=com
#   OU=InstantClones,OU=VDI,DC=contoso,DC=com
#
# Leave empty to search across all synced computer objects.
$HybridJoinConfig = @{
    # Time window to consider newly created VDI computer objects.
    RecentMinutes = 20

    # Minimum wait time between AAD Connect delta sync cycles.
    DeltaSyncMinIntervalMinutes = 10

    VdiSearchBases = @(
        # "OU=HorizonVDI,OU=Desktops,DC=contoso,DC=com"
    )
}
