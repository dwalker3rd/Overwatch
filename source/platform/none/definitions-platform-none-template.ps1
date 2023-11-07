#region PLATFORM DEFINITIONS

$global:Platform = $global:Catalog.Platform.None
$global:Platform.Image = "$($global:Location.Images)/none.png"

$global:PlatformStatusColor = @{
    Degraded = "DarkRed"
    Stopping = "DarkYellow"
    Stopped = "DarkRed"
    Starting = "DarkYellow"
    Restarting = "DarkYellow"
    Running = "DarkGreen"
    Ready = "DarkGreen"
    Queued = "DarkGreen"
    Unknown = "DarkYellow"
    Disabled = "DarkRed"
}

#endregion PLATFORM DEFINITIONS