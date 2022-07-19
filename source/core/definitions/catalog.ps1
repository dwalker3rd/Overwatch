$global:Catalog = @{}
$global:Catalog.Platform = @{}
$global:Catalog.Product = [ordered]@{}

$global:Catalog.Platform += @{ TableauServer = 
    [Platform]@{
        Id = "TableauServer"
        Name = "Tableau Server"
        DisplayName = "Tableau Server"
        Image = "$($global:Location.Images)/tableau_sparkle.png"
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
        Image = "$($global:Location.Images)/tableau_sparkle.png"
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
        Api = @{
            TableauServerRestApi = @{ Version = "3.15" }
            TsmApi = @{ Version = "0.5" }
        }
        Publisher = "Tableau Software, LLC, A Salesforce Company"
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
        Image = "$($global:Location.Images)/alteryx_a_logo.png"
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
    }
}

$global:Catalog.Product += @{ Backup = 
    [Product]@{
        Id = "Backup"
        Name = "Backup"
        DisplayName = "Backup"
        Description = "Manages backups for the platform."
        Publisher = "Overwatch"
    }
}

$global:Catalog.Product += @{ Cleanup = 
    [Product]@{
        Id = "Cleanup"
        Name = "Cleanup"
        DisplayName = "Cleanup"
        Description = "Manages file and data assets for the platform."
        Publisher = "Overwatch"
    }
}

$global:Catalog.Product += @{ DiskCheck = 
    [Product]@{
        Id = "DiskCheck"
        Name = "DiskCheck"
        DisplayName = "DiskCheck"
        Description = "Monitors storage devices critical to the platform."
        Publisher = "Overwatch"
    }
}

$global:Catalog.Product += @{ AzureADCache = 
    [Product]@{
        Id = "AzureADCache"
        Name = "AzureADCache"
        DisplayName = "AzureADCache"
        Description = "Persists Azure AD groups and users in a local cache."
        Publisher = "Overwatch"
        Installation = @{
            Flag = @("NoPrompt")
            Prerequisite = @{
                Service = @("AzureAD")
            }
        }
    }
}

$global:Catalog.Product += @{ AzureADSyncTS = 
    [Product]@{
        Id = "AzureADSyncTS"
        Name = "AzureADSyncTS"
        DisplayName = "AzureADSyncTS"
        Description = "Syncs Active Directory users to Tableau Server."
        Publisher = "Overwatch"
        Installation = @{
            Prerequisite = @{
                Platform = @("TableauServer")
                Service = @("AzureAD")
                Product = @("AzureADCache")
            }
        }
    }
}

$global:Catalog.Product += @{ AzureADSyncB2C = 
    [Product]@{
        Id = "AzureADSyncB2C"
        Name = "AzureADSyncB2C"
        DisplayName = "AzureADSyncB2C"
        Description = "Syncs Azure AD users to Azure AD B2C."
        Publisher = "Overwatch"
        Installation = @{
            Prerequisite = @{
                Platform = @("TableauServer")
                Service = @("AzureAD")
                Product = @("AzureADCache")
            }
        }
    }
}

$global:Catalog.Product += @{ StartRMTAgents = 
    [Product]@{
        Id = "StartRMTAgents"
        Name = "StartRMTAgents"
        DisplayName = "StartRMTAgents"
        Description = "Starts TableauRMT agents."
        Publisher = "Overwatch"
        Installation = @{
            Prerequisite = @{
                Platform = @("TableauRMT")
            }
        }
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
        Config = @{
            MessageType = $PlatformMessageType.UserNotification
        }
        Installation = @{
            Prerequisite = @{
                Platform = @("TableauServer")
            }
        }
    }
}