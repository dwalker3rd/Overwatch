
# catalog.ps1 is executed AFTER classes.ps1 but BEFORE any other definitions file
# therefore the catalog may reference classes, but no references should be made to any other definitions

$global:Catalog = @{}
$global:Catalog.Overwatch = @{}
$global:Catalog.OS = @{}
$global:Catalog.Platform = @{}
$global:Catalog.Product = @{}
$global:Catalog.Provider = @{}

$global:Catalog.Overwatch = 
    [Overwatch]@{
        Id = "Overwatch"
        Name = "Overwatch"
        DisplayName = "Overwatch 2.0"
        Description = ""
        Version = "2.0"
    }

$global:Catalog.OS += @{ WindowsServer = 
    [OS]@{
        Id = "WindowsServer"
        Name = "Windows Server"
        DisplayName = "Windows Server"
        Image = "../img/windows_server.png"  
    }
}

$global:Catalog.Platform += @{ TableauServer = 
    [Platform]@{
        Id = "TableauServer"
        Name = "Tableau Server"
        DisplayName = "Tableau Server"
        Image = "../img/tableau_sparkle.png"
        Description = "Tableau Server"
        Publisher = "Tableau Software, LLC, A Salesforce Company"
        Api = @{
            TableauServerRestApi = @{
                Version = "3.15"
                Prerequisite = @(
                    @{ Type = "PlatformService"; Service = "vizportal"; Status = "Running"; Message = "The Tableau Server REST API is unavailable."}
                )
            }
            TsmApi = @{
                Version = "0.5"
                Prerequisite = @(
                    @{ Type = "Service"; Service = "tabadmincontroller_0"; Status = "Running"; Message = "The TSM REST API is unavailable."}
                )
            }
        }
        Installation = @{
            Discovery = @{
                Service = @("tabadmincontroller_0")
            }
            Prerequisite = @{
                Service = @("TableauServer")
            }
        }
    }
}

$global:Catalog.Platform += @{ TableauCloud = 
    [Platform]@{
        Id = "TableauCloud"
        Name = "Tableau Cloud"
        DisplayName = "Tableau Cloud"
        Image = "../img/tableau_sparkle.png"
        Description = "Tableau Cloud"
        Publisher = "Tableau Software, LLC, A Salesforce Company"
        Api = @{
            TableauServerRestApi = @{
                Version = "3.16"
            }
        }
    }
}

$global:Catalog.Platform += @{ TableauRMT = 
    [Platform]@{
        Id = "TableauRMT"
        Name = "Tableau RMT"
        DisplayName = "Tableau Resource Monitoring Tool"
        Description = "Tableau Resource Monitoring Tool"
        Publisher = "Tableau Software, LLC, A Salesforce Company"
        Api = @{
            TableauServerRestApi = @{ Version = "3.15" }
            TsmApi = @{ Version = "0.5" }
        }
        Installation = @{
            Discovery = @{
                Service = @("TableauResourceMonitoringTool")
            }
            Prerequisite = @{
                Service = @("TableauServer")
            }
        }
    }
}

$global:Catalog.Platform += @{ AlteryxServer = 
    [Platform]@{
        Id = "AlteryxServer"
        Name = "Alteryx Server"
        DisplayName = "Alteryx Server"
        Image = "../img/alteryx_a_logo.png"
        Description = "Alteryx Server"
        Publisher = "Alteryx, Inc."
        Installation = @{
            Discovery = @{
                Service = @("AlteryxService")
            }
        }
    }
}

$global:Catalog.Product += @{ Command = 
    [Product]@{
        Id = "Command"
        Name = "Command"
        DisplayName = "Command"
        Description = "A command interface for managing the platform."
        Publisher = "Overwatch"
        Log = "Command"
        Installation = @{
            Flag = @("AlwaysInstall","UninstallProtected")
        }
    }
}

$global:Catalog.Product += @{ Monitor = 
    [Product]@{
        Id = "Monitor"
        Name = "Monitor"
        DisplayName = "Monitor"
        Description = "Monitors the health and activity of the platform."
        Publisher = "Overwatch"
        HasTask = $true
    }
}

$global:Catalog.Product += @{ Backup = 
    [Product]@{
        Id = "Backup"
        Name = "Backup"
        DisplayName = "Backup"
        Description = "Manages backups for the platform."
        Publisher = "Overwatch"
        HasTask = $true
    }
}

$global:Catalog.Product += @{ Cleanup = 
    [Product]@{
        Id = "Cleanup"
        Name = "Cleanup"
        DisplayName = "Cleanup"
        Description = "Manages file and data assets for the platform."
        Publisher = "Overwatch"
        HasTask = $true
    }
}

$global:Catalog.Product += @{ DiskCheck = 
    [Product]@{
        Id = "DiskCheck"
        Name = "DiskCheck"
        DisplayName = "DiskCheck"
        Description = "Monitors storage devices critical to the platform."
        Publisher = "Overwatch"
        HasTask = $true
    }
}

$global:Catalog.Product += @{ AzureADCache = 
    [Product]@{
        Id = "AzureADCache"
        Name = "AzureADCache"
        DisplayName = "AzureADCache"
        Description = "Persists Azure AD groups and users in a local cache."
        Publisher = "Overwatch"
        HasTask = $true
        Installation = @{
            Flag = @("NoPrompt")
            Prerequisite = @{
                Service = @("AzureAD")
            }
        }
        Family = "AzureADSync"
    }
}

$global:Catalog.Product += @{ AzureADSyncTS = 
    [Product]@{
        Id = "AzureADSyncTS"
        Name = "AzureADSyncTS"
        DisplayName = "AzureADSyncTS"
        Description = "Syncs Active Directory users to Tableau Server."
        Publisher = "Overwatch"
        HasTask = $true
        Installation = @{
            Prerequisite = @{
                Platform = @("TableauServer")
                Service = @("AzureAD")
                Product = @("AzureADCache")
            }
        }
        Family = "AzureADSync"
    }
}

$global:Catalog.Product += @{ AzureADSyncB2C = 
    [Product]@{
        Id = "AzureADSyncB2C"
        Name = "AzureADSyncB2C"
        DisplayName = "AzureADSyncB2C"
        Description = "Syncs Azure AD users to Azure AD B2C."
        Publisher = "Overwatch"
        HasTask = $true
        Installation = @{
            Prerequisite = @{
                Platform = @("TableauServer")
                Service = @("AzureAD")
                Product = @("AzureADCache")
            }
        }
        Family = "AzureADSync"
    }
}

$global:Catalog.Product += @{ StartRMTAgents = 
    [Product]@{
        Id = "StartRMTAgents"
        Name = "StartRMTAgents"
        DisplayName = "StartRMTAgents"
        Description = "Starts TableauRMT agents."
        Publisher = "Overwatch"
        HasTask = $true
        Installation = @{
            Prerequisite = @{
                Platform = @("TableauRMT")
            }
        }
    }
}

$global:Catalog.Product += @{ AzureProjects = 
    [Product]@{
        Id = "AzureProjects"
        Name = "AzureProjects"
        DisplayName = "AzureProjects"
        Description = "Manages Azure projects based on resource groups."
        Publisher = "Overwatch"
        Installation = @{
            Prerequisite = @{
                Service = @("Azure","AzureAD")
            }
        }
    }
}

$global:Catalog.Product += @{ AzureRunCommand = 
    [Product]@{
        Id = "AzureRunCommand"
        Name = "AzureRunCommand"
        DisplayName = "AzureRunCommand"
        Description = "Allows Azure to run remote Overwatch commands."
        Publisher = "Overwatch"
    }
}

$global:Catalog.Product += @{ BgInfo = 
    [Product]@{
        Id = "BgInfo"
        Name = "BgInfo"
        DisplayName = "BgInfo"
        Description = "Automation for BgInfo from Microsoft Sysinternals"
        Publisher = "Overwatch"
        HasTask = $false
    }
}

$global:Catalog.Provider += @{ SMTP = 
    [Provider]@{
        Id = "SMTP"
        Name = "SMTP"
        DisplayName = "SMTP"
        Category = "Messaging"
        Description = "Overwatch messaging via SMTP"
        Publisher = "Overwatch"
        Log = "SMTP"
    }
}

$global:Catalog.Provider += @{ TwilioSMS = 
    [Provider]@{
        Id = "TwilioSMS"
        Name = "Twilio SMS"
        DisplayName = "Twilio SMS"
        Category = "Messaging"
        Description = "Overwatch messaging via Twilio SMS"
        Publisher = "Overwatch"
        Log = "TwilioSMS"
    }
}

$global:Catalog.Provider += @{ MicrosoftTeams = 
    [Provider]@{
        Id = "MicrosoftTeams"
        Name = "Microsoft Teams"
        DisplayName = "Microsoft Teams"
        Category = "Messaging"
        Description = "Overwatch messaging via Microsoft Teams"
        Publisher = "Overwatch"
        Log = "MicrosoftTeams"
    }
}

$global:Catalog.Provider += @{ Views = 
    [Provider]@{
        Id = "Views"
        Name = "Views"
        DisplayName = "Views"
        Category = "Formatting"
        Description = "Predefined PowerShell Format-Table views for Overwatch functions"
        Publisher = "Overwatch"
        Log = "Views"
        Installation = @{
            Flag = @("AlwaysInstall","UninstallProtected")
        }
    }
}

$global:Catalog.Provider += @{ Postgres = 
    [Provider]@{
        Id = "Postgres"
        Name = "Postgres"
        DisplayName = "Postgres"
        Category = "Database"
        Description = "Postgres database provider"
        Publisher = "Overwatch"
        Log = "Postgres"
    }
}

$global:Catalog.Provider += @{ TableauServerWC = 
    [Provider]@{
        Id = "TableauServerWC"
        Name = "TableauServerWC"
        DisplayName = "Tableau Server Welcome Channel"
        Category = "Messaging"
        Description = "Tableau Server user notifications via the welcome channel (welcome banner)"
        Publisher = "Overwatch"
        Log = "TableauServerWC"
        Config = @{
            MessageType = $PlatformMessageType.UserNotification
        }
        Installation = @{
            Prerequisite = @{
                Platform = @("TableauServer")
                Provider = @("Postgres")
            }
        }
    }
}

$global:Catalog.Provider += @{ Okta = 
    [Provider]@{
        Id = "Okta"
        Name = "Okta"
        DisplayName = "Okta"
        Category = "Identity"
        Description = "Okta Identity Provider"
        Publisher = "Overwatch"
        Log = "Okta"
    }
}