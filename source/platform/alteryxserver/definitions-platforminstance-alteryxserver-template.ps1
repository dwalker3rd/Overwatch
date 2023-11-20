﻿<# 
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

    $global:Platform.Instance = "alteryx-path-org"
    $global:Platform.Uri = [System.Uri]::new("https://alteryx.path.org/gallery")
    $global:Platform.Domain = "path.org"
    $global:Platform.InstallPath = "F:\Program Files\Alteryx"

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
            Nodes = @('ayx-control-01', 'ayx-gallery-01', 'ayx-gallery-02', 'ayx-worker-01', 'ayx-worker-02', 'ayx-worker-03', 'ayx-worker-04')
            Components = @("Controller", "Database", "Gallery", "Worker")
        }
        $global:PlatformTopologyDefaultComponentMap = @{
            Nodes = @{
                'ayx-control-01' = "Controller"
                'ayx-gallery-01' = "Gallery"
                'ayx-gallery-02' = "Gallery"
                'ayx-worker-01' = "Worker"
                'ayx-worker-02' = "Worker"
                'ayx-worker-03' = "Worker"
                'ayx-worker-04' = "Worker"
            }
        }

        # $global:PlatformTopologyBase = @{
        #     Nodes = @('ayx-control-01', 'ayx-gallery-01', 'ayx-gallery-02', 'ayx-worker-01', 'ayx-worker-02', 'ayx-worker-03', 'ayx-worker-04')
        #     Components = @("Controller", "Database", "Gallery", "Worker")
        # }

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
            AlteryxService = @{
                LogFiles = @{
                    # Filter derived from controller runtime settings
                    Retention = "15D" 
                }
            }
            Controller = @{}
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
            Gallery = @{
                LogFiles = @{
                    Filter = "alteryx-*.csv"
                    Retention = "15D" 
                } 
            }
            Worker = @{
                StagingFiles = @{
                    Filter = @("*_????????????????????????????????")
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

        $global:OverwatchRemoteControllers += @("tbl-prod-01","tbl-test-01","tbl-mgmt-01","app-01")
        $global:OverwatchControllers += $global:OverwatchRemoteControllers

    #endregion OVERWATCH TOPOLOGY     

#endregion INSTANCE-DEFINITIONS

