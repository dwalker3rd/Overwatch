# The following line indicates a post-installation configuration to the installer
# Manual Configuration > Definitions > Sysinternals > Edit

$global:Sysinternals = @{
    SysinternalsLive = [uri]"https://live.sysinternals.com"
    AutoUpdate = $false
}

$global:Location.Sysinternals = "$($global:Location.Root)\sysinternals"