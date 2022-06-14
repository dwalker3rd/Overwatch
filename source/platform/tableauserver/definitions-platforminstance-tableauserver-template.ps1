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

.Parameter Backup
Platform-specific object.  See platform definition file.

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

.Parameter AzureADSync
If using AzureADSync for Tableau Server, enter the site id[s] here.

#>

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

    #region BACKUPS

        $global:Backup = $null
        $global:Backup += @{
            Path = "<backupArchiveLocation>"
            Name = "$($global:Environ.Instance).$(Get-Date -Format 'yyyyMMddHHmm')"
            Extension = "bak"
            Keep = 3
            MaxRunTime = New-Timespan -Minutes 15
        }
        $global:Backup += @{File = "$($Backup.Path)\$($Backup.Name).$($Backup.Extension)"}

    #endregion BACKUPS

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
                Information = @("<Microsoft Teams Information Webhook>")
                Warning = @("<Microsoft Teams Warning Webhook>")
            }
            MessageType = $MicrosoftTeamsConfig.Connector.Keys
        }

    #endregion MICROSOFT-TEAMS

    #region AZUREADSYNC

        # The following line indicates a post-installation configuration to the installer
        # Manual Configuration > Product > AzureADSyncTS > Data

        $global:AzureADSyncTS = @{
            Sites = @{
                ContentUrl = @()
            }
            PathOperations = @{
                SiteRoleMinimum = "Viewer"
            }
        }
    
    #endregion AZUREADSYNC

    #region PLATFORM TOPOLOGY ALIASES

        # The following line indicates a post-installation configuration to the installer
        # Manual Configuration > Platform > Topology > Update Alias Regex [OPTIONAL]

        $global:RegexPattern += @{
            PlatformTopology = @{
                Alias = @{
                    Match = "" # enter Regex pattern here for creating platform topology aliases from node names
                    Groups = @()
                }
            }
        }

    #endregion PLATFORM TOPOLOGY ALIASES

#endregion INSTANCE-DEFINITIONS