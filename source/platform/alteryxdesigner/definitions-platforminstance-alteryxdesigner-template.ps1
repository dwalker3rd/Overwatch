<# 
.Synopsis
Template for an Alteryx Server platform instance
.Description
Template for an Alteryx Server platform instance

.Parameter Instance
User-supplied ID for the platform instance. Must be unique.
Format: $Environ.Instance -match "^([a-zA-Z]+-?)+$"
.Parameter Uri
The uri for the platform instance
.Parameter Domain
The domain of the platform instance
.Parameter InstallPath
The location where the platform software is installed.

.Parameter PrincipalContextType 
Security context for the instance
Supported options: Machine or Domain
Link: https://docs.microsoft.com/en-us/dotnet/api/system.directoryservices.accountmanagement.contexttype
.Parameter PrincipalContextName
If PrincipalContextType -eq "Machine", then the machine name
If PrincipalContextType -eq "Domain", then the domain name

.Parameter PlatformComponentTimeout
Consider a platform component to have failed if unresponsive to a command after this period.
.Parameter PlatformShutdownMax
Alert if a platform is shutdown (manually or for backups) longer than this period.

.Parameter diskSpaceLowThreshold
The percentage at which free space on a disk is considered LOW
.Parameter diskSpaceCriticalThreshold
The percentage at which free space on a disk is considered CRITICALLY LOW
.Parameter ignoreDriveType
Disks by drive type which should be ignored
Link:  https://docs.microsoft.com/en-us/dotnet/api/system.io.drivetype
.Parameter ignoreDisks 
Disks by volume which should be ignored

.Parameter MicrosoftTeamsConfig
If using the Microsoft Teams provider, it must be configured here.

#>

#region INSTANCE-DEFINITIONS

    #region PLATFORM-OBJECT

    $global:Platform.Instance = "$($env:COMPUTERNAME.ToLower()).path.org"
    $global:Platform.Uri = $null
    $global:Platform.Domain = "path.org"
    $global:Platform.InstallPath = Invoke-Command $global:Catalog.Platform.AlteryxDesigner.Installation.InstallLocation

    #endregion PLATFORM-OBJECT
    #region PLATFORMTOPOLOGY

        $global:RegexPattern += @{
            PlatformTopology = @{
                Alias = @{
                    Match = "^.*?-(.*?)-0?(\d{1,2})$"
                    Groups = @(1,2)
                }
            }
        }

        # ATTENTION!
        # Nodes should ONLY be removed from the hard-coded nodes definition below 
        # IFF Alteryx Server has been uninstalled, reconfigured for another instance of
        # Alteryx Server or the node has been decommissioned.  For temporary removal,
        # use the REMOVE or OFFLINE functions.

        $global:PlatformTopologyBase = @{
            Nodes = @('ayx-designer-01')
            Components = @("Designer")
        }
        $global:PlatformTopologyDefaultComponentMap = @{
            'ayx-designer-01' = "Designer"
        }

    #endregion PLATFORMTOPOLOGY
    #region PLATFORM-TIMEOUTS

        $global:PlatformComponentTimeout = 300
        $global:PlatformShutdownMax = New-TimeSpan -Minutes 75   

    #endregion PLATFORM-TIMEOUTS
    #region PRINCIPAL-CONTEXT

        $global:PrincipalContextType = [System.DirectoryServices.AccountManagement.ContextType]::Machine  
        $global:PrincipalContextName = $env:COMPUTERNAME

    #endregion PRINCIPAL-CONTEXT
    #region CLEANUP

        $global:Cleanup = $null
        $global:Cleanup += @{
            Default = @{
                Retention = "15D"
            }
            Engine = @{
                TempFiles = @{
                    Filter = @("Alteryx_*_","AlteryxCEF_*")
                    Retention = "15D" 
                }
                LogFiles = @{
                    Filter = "*.log"
                    Retention = "15D" 
                }
                StagingFiles = @{
                    Filter = @("????????-????-????-????-????????????")
                    Retention = "15D"
                }
            }           
        }

    #endregion CLEANUP
    #region DISKS

        $global:diskSpaceLowThreshold = 15
        $global:diskSpaceCriticalThreshold = 10
        $global:ignoreDriveType = @(2,5)
        $global:ignoreDisks = @("D:")

    #endregion DISKS
    #region MICROSOFT-TEAMS

        # If using the MicrosoftTeams provider, enter the webhook URI[s] for each message type (see $PlatformMessageType)
        # $MicrosoftTeamsConfig.MessageType defines which message types are forwarded by the MicrosoftTeams provider

        $global:MicrosoftTeamsConfig = @{
            Connector = @{
                AllClear = @("***REMOVED***",
                             "***REMOVED***")
                Alert = @("***REMOVED***",
                          "***REMOVED***")
                Heartbeat = @("***REMOVED***")
                Information = @("***REMOVED***")
                Intervention = @("***REMOVED***",
                                 "***REMOVED***") 
                Warning = @("***REMOVED***",
                            "***REMOVED***")
            }
        }
        $global:MicrosoftTeamsConfig.MessageType = $global:MicrosoftTeamsConfig.Connector.Keys

    #endregion MICROSOFT-TEAMS
    #region PYTHON

        $global:Location += @{
            Python = @{
                Pip = "F:\Program Files\Alteryx\bin\Miniconda3\envs\DesignerBaseTools_vEnv\Scripts"
                SitePackages = "F:\Program Files\Alteryx\bin\Miniconda3\envs\DesignerBaseTools_vEnv\Lib\site-packages"
            }
        }

        $global:RequiredPythonPackages = @('tableauhyperapi', 'tableauserverclient==0.25', 'shapely', 'html2text', 'google-cloud-storage', 'azure-storage-blob')

    #endregion PYTHON

    #region TLS BEST PRACTICES
        
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

    #region OVERWATCH TOPOLOGY 

        $global:OverwatchRemoteControllers += @()
        $global:OverwatchControllers += $global:OverwatchRemoteControllers

    #endregion OVERWATCH TOPOLOGY     

#endregion INSTANCE-DEFINITIONS