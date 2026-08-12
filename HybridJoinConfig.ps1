# HybridJoinConfig.ps1
# Configure customer-specific settings here.
#
# Use distinguished names (DN) for AD OU paths, for example:
#   OU=HorizonVDI,OU=Desktops,DC=contoso,DC=com
#   OU=InstantClones,OU=VDI,DC=contoso,DC=com
#
# Leave empty to search across all synced computer objects.
$HybridJoinConfig = @{
    # Time window to consider newly created VDI computer objects. Older objects
    # are also processed when their userCertificate fingerprint changes.
    RecentMinutes = 20

    # Minimum wait time between AAD Connect delta sync cycles.
    DeltaSyncMinIntervalMinutes = 10

    # IMPORTANT: Leaving VdiSearchBases empty will search ALL computer objects in AD.
    # In large environments this can be very slow and return unrelated machines.
    # Specify one or more OU distinguished names to scope the search.
    VdiSearchBases = @(
        # "OU=HorizonVDI,OU=Desktops,DC=contoso,DC=com"
    )

    # Path for the log file. Leave empty to write HybridJoin.log to the script directory.
    # Use an absolute path when running as a scheduled task under a service account
    # that may not have write access to the script directory.
    # Example: "C:\Logs\HybridJoinMonitor\HybridJoin.log"
    LogPath = ""

    # Path for certificate fingerprint state. Leave empty to write
    # HybridJoinState.json to the script directory.
    # Example: "C:\ProgramData\HybridJoinMonitor\HybridJoinState.json"
    StatePath = ""
}
