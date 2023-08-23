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
                Heartbeat = @("<Microsoft Teams Heartbeat Webhook>")
                Information = @("<Microsoft Teams Information Webhook>")
                Intervention = @("<Microsoft Teams Intervention Webhook>")
                Warning = @("<Microsoft Teams Warning Webhook>")
            }
        }
        $global:MicrosoftTeamsConfig.MessageType = $MicrosoftTeamsConfig.Connector.Keys

    #endregion MICROSOFT-TEAMS

    #region TLS BEST PRACTICES
    
        # The following line indicates a post-installation configuration to the installer
        # Manual Configuration > PlatformInstance > BestPractice > TLS
        
        $global:TlsBestPractices = @{
            Protocols = @{
                Ssl2  = @{state="Disabled"; displayName="SSLv2"}
                Ssl3  = @{state="Disabled"; displayName="SSLv3"}
                Tls   = @{state="Disabled"; displayName="TLSv1"}
                Tls11 = @{state="Disabled"; displayName="TLSv1.1"}
                Tls12 = @{state="Enabled"; displayName="TLSv1.2"}
                Tls13 = @{state="Optional"; displayName="TLSv1.3"}
            }
            # signatureAlgorithms = @("sha256RSA")
        }

    #endregion TLS BEST PRACTICES    

#endregion INSTANCE DEFINITIONS