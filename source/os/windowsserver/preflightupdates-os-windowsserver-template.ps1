#region PREFLIGHT

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    # The following line indicates a post-installation configuration to the installer
    # Optional > Manual Configuration > WindowsServer > Group Policy

    # Update-GroupPolicy maintains the group policy of each node in the platform topology
    # with the group policy file (.pol) located in $global:Location.Data.  This is an easy 
    # way to ensure new/updated nodes have the same group policy which includes settings
    # for winrm and credSSP.
    
    # Update-GroupPolicy -ComputerName (pt nodes -k) -Update

#endregion PREFLIGHT