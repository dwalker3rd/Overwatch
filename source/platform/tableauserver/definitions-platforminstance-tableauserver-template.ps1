#region INSTANCE-DEFINITIONS

    #region PLATFORM-OBJECT

        $global:Platform.Instance = "<platformInstanceId>"
        $global:Platform.Uri = [System.Uri]::new("<platformInstanceUrl>")
        $global:Platform.Domain = "<platformInstanceDomain>"
        $global:Platform.InstallPath = "<platformInstallLocation>"

    #endregion PLATFORM-OBJECT

    #region PLATFORM-TIMEOUTS

        $global:PlatformComponentTimeout = 300
        $global:PlatformShutdownMax = New-TimeSpan -Minutes 75   

    #endregion PLATFORM-TIMEOUTS

    #region PRINCIPAL-CONTEXT

        $global:PrincipalContextType = [System.DirectoryServices.AccountManagement.ContextType]::Machine  
        $global:PrincipalContextName = $env:COMPUTERNAME

    #endregion PRINCIPAL-CONTEXT

    #region CLEANUP

        # The following line indicates a post-installation configuration to the installer
        # Manual Configuration > Product > Cleanup > Customization

        # $global:Cleanup = $null
        # $global:Cleanup += @{
        #     All = $false
        #     BackupFiles = $false
        #     BackupFilesRetention = 3
        #     LogFiles = $true
        #     LogFilesRetention = 1
        #     HttpRequestsTable = $false
        #     HttpRequestsTableRetention = 7
        #     TempFiles = $true 
        #     RedisCache = $false 
        #     SheetImageCache = $false
        #     TimeoutInSeconds = 0
        # }  

    #endregion CLEANUP    

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
                AllClear = @("<Microsoft Teams AllClear Webhook>")
                Alert = @("<Microsoft Teams Alert Webhook>","<Microsoft Teams Alert Webhook>")
                # Heartbeat = @("<Microsoft Teams Heartbeat Webhook>")
                Information = @("<Microsoft Teams Information Webhook>")
                Intervention = @("<Microsoft Teams Intervention Webhook>")
                Warning = @("<Microsoft Teams Warning Webhook>")
            }
        }
        $global:MicrosoftTeamsConfig.MessageType = $MicrosoftTeamsConfig.Connector.Keys

    #endregion PROVIDER-MICROSOFT-TEAMS

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

    #region PLATFORM-TOPOLOGY-ALIASES

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

    #endregion PLATFORM-TOPOLOGY-ALIASES
    
    #region TLS-BEST-PRACTICES
    
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

    #endregion TLS-BEST-PRACTICES   

    #region OVERWATCH-TOPOLOGY

        # The following line indicates a post-installation configuration to the installer
        # Manual Configuration > Platform > Topology > Update Overwatch Remote Controllers    

        $global:OverwatchRemoteControllers += @()
        $global:OverwatchControllers += $global:OverwatchRemoteControllers

    #endregion OVERWATCH-TOPOLOGY    

#endregion INSTANCE-DEFINITIONS