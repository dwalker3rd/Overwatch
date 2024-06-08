#region INSTANCE-DEFINITIONS

    #region PLATFORM-OBJECT

        $global:Platform.Instance = "None"

    #endregion PLATFORM-OBJECT

    #region PLATFORM-TIMEOUTS

        $global:PlatformComponentTimeout = 300
        $global:PlatformShutdownMax = New-TimeSpan -Minutes 75   

    #endregion PLATFORM-TIMEOUTS

    #region PRINCIPAL-CONTEXT

        $global:PrincipalContextType = [System.DirectoryServices.AccountManagement.ContextType]::Machine  
        $global:PrincipalContextName = $env:COMPUTERNAME

    #endregion PRINCIPAL-CONTEXT

    #region DISKS

        $global:diskSpaceLowThreshold = 15
        $global:diskSpaceCriticalThreshold = 10
        $global:ignoreDriveType = @(2,5)
        $global:ignoreDisks = @("D:")

    #endregion DISKS  

    #region MICROSOFT-TEAMS

        # The following line indicates a post-installation configuration to the installer
        # Manual Configuration > Provider > MicrosoftTeams > Webhooks

        # If using the MicrosoftTeams provider, enter the webhook URI[s] for each message type (see $PlatformMessageType)
        # $MicrosoftTeamsConfig.MessageType defines which message types are forwarded by the MicrosoftTeams provider

        $global:MicrosoftTeamsConfig = @{
            Connector = @{
                Alert = @("<Microsoft Teams Alert Webhook>","<Microsoft Teams Alert Webhook>")
                AllClear = @("<Microsoft Teams AllClear Webhook>")
                # Heartbeat = @("<Microsoft Teams Heartbeat Webhook>")
                # Information = @("<Microsoft Teams Information Webhook>")
                Intervention = @("<Microsoft Teams Intervention Webhook>")
                Warning = @("<Microsoft Teams Warning Webhook>")
            }
        }
        $global:MicrosoftTeamsConfig.MessageType = $MicrosoftTeamsConfig.Connector.Keys

    #endregion MICROSOFT-TEAMS

    #region SMS

        $global:SMSConfig = @{
            From = "<SMS From>"
            To = @()
            Throttle = New-TimeSpan -Minutes 15
            MessageType = @($PlatformMessageType.Intervention)
        }
        $global:SMSConfig += @{RestEndpoint = "https://api.twilio.com/2010-04-01/Accounts/<AccountSID>/Messages.json"}

    #endregion SMS

    #region SMTP

        $global:SmtpConfig = @{
            Server = "<SMTP Server>"
            Port = "<SMTP Port>"
            UseSsl = "<SMTP UseSSL>" -eq "True"
            MessageType = @($PlatformMessageType.Warning,$PlatformMessageType.Alert,$PlatformMessageType.AllClear,$PlatformMessageType.Intervention)
            From = $null # deferred to provider
            To = @() # deferred to provider
            Throttle = New-TimeSpan -Minutes 15
        }

    #endregion SMTP      

    #region PLATFORM TOPOLOGY ALIASES

        # The following line indicates a post-installation configuration to the installer
        # Manual Configuration > Platform > Topology > Update Alias Regex [OPTIONAL]

        $global:RegexPattern += @{
            PlatformTopology = @{
                Alias = @{
                    Match = ".*" # enter Regex pattern here for creating platform topology aliases from node names
                    Groups = @(0)
                }
            }
        }

    #endregion PLATFORM TOPOLOGY ALIASES 

    #region OVERWATCH TOPOLOGY

        # The following line indicates a post-installation configuration to the installer
        # Manual Configuration > Platform > Topology > Update Overwatch Remote Controllers    

        $global:OverwatchRemoteControllers += @()
        $global:OverwatchControllers += $global:OverwatchRemoteControllers

    #endregion OVERWATCH TOPOLOGY    

    #region TRACE OVERWATCH CONTROLLERS

        $global:TestOverwatchControllers = $true

    #endregion TRACE OVERWATCH CONTROLLERS

#endregion INSTANCE-DEFINITIONS