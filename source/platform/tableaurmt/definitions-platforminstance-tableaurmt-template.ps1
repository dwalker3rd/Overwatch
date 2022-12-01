#region INSTANCE DEFINITIONS

    $global:Platform.Instance = "<platformInstanceId>"
    $global:Platform.Uri = [System.Uri]::new("<platformInstanceUrl>")
    $global:Platform.Domain = "<platformInstanceDomain>"
    $global:Platform.InstallPath = "<platformInstallLocation>"

    $controller = $env:COMPUTERNAME.ToLower()
    $global:PlatformTopologyBase.Components.Controller.Nodes += @{ $controller = @{} }
    $global:PlatformTopologyBase.Components.Controller.Nodes.$controller += @{ Instances = @{} }

    #region DISKS
        $global:diskSpaceLowThreshold = 15
        $global:diskSpaceCriticalThreshold = 10
        $global:ignoreDriveType = (2,5)
        $global:ignoreDisks = @("D:")
    #region DISKS

    # see https://docs.microsoft.com/en-us/dotnet/api/system.directoryservices.accountmanagement.contexttype
    $global:PrincipalContextType = [System.DirectoryServices.AccountManagement.ContextType]::Machine
    $global:PrincipalContextName = $env:COMPUTERNAME

    $global:PlatformComponentTimeout = 300
    $global:PlatformShutdownMax = New-TimeSpan -Minutes 75

    #region MICROSOFT-TEAMS

        # The following line indicates a post-installation configuration to the installer
        # Manual Configuration > Provider > MicrosoftTeams > Webhooks

        # If using the MicrosoftTeams provider, enter the webhook URI[s] for each message type (see $PlatformMessageType)
        # $MicrosoftTeamsConfig.MessageType defines which message types are forwarded by the MicrosoftTeams provider

        $global:MicrosoftTeamsConfig = @{
            Connector = @{
                AllClear = @("<Microsoft Teams AllClear Webhook>")
                Alert = @("<Microsoft Teams Alert Webhook>","<Microsoft Teams Alert Webhook>")
                Information = @("<Microsoft Teams Information Webhook>")
                Warning = @("<Microsoft Teams Warning Webhook>")
            }
        }
        $global:MicrosoftTeamsConfig.MessageType = $MicrosoftTeamsConfig.Connector.Keys

    #endregion MICROSOFT-TEAMS

#endregion INSTANCE DEFINITIONS