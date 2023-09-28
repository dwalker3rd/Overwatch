
$global:Catalog = @{}
$global:Catalog.Overwatch = @{}
$global:Catalog.Cloud = @{}
$global:Catalog.OS = @{}
$global:Catalog.Platform = @{}
$global:Catalog.Product = @{}
$global:Catalog.Provider = @{}
$global:Catalog.Installer = @{}
$global:Catalog.Driver = @{}

$global:Catalog.Overwatch += @{ Overwatch =  
    [Overwatch]@{
        Id = "Overwatch"
        Name = "Overwatch"
        DisplayName = "Overwatch"
        Description = ""
        Release = "2.1"
        Publisher = "Walker Analytics Consulting"
        Installation = @{
            Registry = @{
                Path = "HKLM:\SOFTWARE\Overwatch"
            }
        }
    }
}

$global:Catalog.OS += @{ WindowsServer = 
    [OS]@{
        Id = "WindowsServer"
        Name = "Windows Server"
        DisplayName = "Windows Server"
        Image = "../img/windows_server.png"  
        Installation = @{
            Prerequisite = @{}
        }
        Description = "Overwatch services for the Microsoft Windows Server operating system"
        Publisher = "Walker Analytics Consulting"
    }
}

$global:Catalog.Cloud += @{ Azure = 
    [Cloud]@{
        Id = "Azure"
        Name = "Azure"
        DisplayName = "Microsoft Azure"
        Image = "../img/azure_logo.png"
        Description = "Overwatch services for the Microsoft Azure cloud"
        Publisher = "Walker Analytics Consulting"
        Log = "Azure"
        Installation = @{
            NoClobber = @(
                "$($global:Location.Definitions)\definitions-cloud-azure.ps1"
            )
            Prerequisite = @{
                PowerShell = @{
                    Module = @(
                        @{ Name = "Az.Accounts" },
                        @{ Name = "Az.Compute" },
                        @{ Name = "Az.Resources" },
                        @{ Name = "Az.Storage" },
                        @{ Name = "Az.Network" },
                        @{ Name = "Az.CosmosDb" },
                        @{ Name = "Az.SqlVirtualMachine" },
                        @{ Name = "Az.KeyVault" },
                        @{ Name = "Az.DataFactory" },
                        @{ Name = "Az.Batch" }
                    )
                }
            }
        }
    }
}

$global:Catalog.Platform += @{ None = 
    [Platform]@{
        Id = "None"
        Name = "None"
        DisplayName = "None"
        Image = "../img/none.png"
        Description = "Ov"
        Publisher = "Walker Analytics Consulting"
    }
}

$global:Catalog.Platform += @{ TableauServer = 
    [Platform]@{
        Id = "TableauServer"
        Name = "Tableau Server"
        DisplayName = "Tableau Server"
        Image = "../img/tableau_sparkle.png"
        Description = "Overwatch services for the Tableau Server platform"
        Publisher = "Walker Analytics Consulting"
        Installation = @{
            Discovery = @(
                @{ Type = "Service"; Service = "tabadmincontroller_0"; Status = "Running" }
            )
            Prerequisite = @{
                Provider = @("TableauServerRestApi","TableauServerTsmApi","TableauServerTabCmd")
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
        Description = "Overwatch services for the Tableau Cloud platform"
        Publisher = "Walker Analytics Consulting"
        Installation = @{
            Discovery = @{}
            Prerequisite = @{
                Provider = @("TableauServerRestApi","TableauServerTabCmd")
            }
        }
    }
}

$global:Catalog.Platform += @{ TableauRMT = 
    [Platform]@{
        Id = "TableauRMT"
        Name = "Tableau RMT"
        DisplayName = "Tableau Resource Monitoring Tool"
        Description = "Overwatch services for Tableau Resource Monitoring Tool, part of Tableau Advanced Management for Tableau Server and Tableau Cloud"
        Publisher = "Walker Analytics Consulting"
        Installation = @{
            Discovery = @(
                @{ Type = "Service"; Service = "TableauResourceMonitoringTool"; Status = "Running" }
            )
            Prerequisite = @{
                Provider = @("TableauServerTsmApi")
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
        Description = "Overwatch services for the Alteryx Server platform"
        Publisher = "Walker Analytics Consulting"
        Installation = @{
            Discovery = @(
                @{ Type = "Service"; Service = "AlteryxService"; Status = "Running" }
            )
            Prerequisite = @{}
        }
    }
}

$global:Catalog.Product += @{ Command = 
    [Product]@{
        Id = "Command"
        Name = "Command"
        DisplayName = "Command"
        Description = "Overwatch command shell."
        Publisher = "Walker Analytics Consulting"
        Log = "Command"
        Installation = @{
            Flag = @("AlwaysInstall","UninstallProtected")
            Prerequisite = @{}
        }
    }
}

$global:Catalog.Product += @{ Monitor = 
    [Product]@{
        Id = "Monitor"
        Name = "Monitor"
        DisplayName = "Monitor"
        Description = "Monitors the health and activity of Overwatch platforms."
        Publisher = "Walker Analytics Consulting"
        HasTask = $true
        Installation = @{
            Prerequisite = @{}
        }
    }
}

$global:Catalog.Product += @{ Backup = 
    [Product]@{
        Id = "Backup"
        Name = "Backup"
        DisplayName = "Backup"
        Description = "Manages backups for Overwatch platforms."
        Publisher = "Walker Analytics Consulting"
        HasTask = $true
        Installation = @{
            Prerequisite = @{
                Platform = @("TableauServer","AlteryxServer")
            }
        }
    }
}

$global:Catalog.Product += @{ Cleanup = 
    [Product]@{
        Id = "Cleanup"
        Name = "Cleanup"
        DisplayName = "Cleanup"
        Description = "Manages resource removal for the Overwatch environment."
        Publisher = "Walker Analytics Consulting"
        HasTask = $true
        Installation = @{
            Prerequisite = @{}
        }
    }
}

$global:Catalog.Product += @{ DiskCheck = 
    [Product]@{
        Id = "DiskCheck"
        Name = "DiskCheck"
        DisplayName = "DiskCheck"
        Description = "Monitors space on operating system disks in the Overwatch environment."
        Publisher = "Walker Analytics Consulting"
        HasTask = $true
        Installation = @{
            Prerequisite = @{}
        }
    }
}

$global:Catalog.Product += @{ AzureADCache = 
    [Product]@{
        Suite = "AzureADSync"
        Id = "AzureADCache"
        Name = "AzureADCache"
        DisplayName = "AzureADCache"
        Description = "Cache for Azure AD and Azure AD B2C data."
        Publisher = "Walker Analytics Consulting"
        HasTask = $true
        Installation = @{
            Flag = @("NoPrompt")
            Prerequisite = @{
                Cloud = @("Azure")
                Provider = @("AzureAD")
            }
        }
    }
}

$global:Catalog.Product += @{ AzureADSyncTS = 
    [Product]@{
        Suite = "AzureADSync"
        Id = "AzureADSyncTS"
        Name = "AzureADSyncTS"
        DisplayName = "AzureADSyncTS"
        Description = "Syncs Azure AD users to Tableau Server."
        Publisher = "Walker Analytics Consulting"
        HasTask = $true
        Installation = @{
            Prerequisite = @{
                Platform = @("TableauServer")
                Cloud = @("Azure")
                Product = @("AzureADCache")
                Provider = @("AzureAD")
            }
        }
    }
}

$global:Catalog.Product += @{ AzureADSyncB2C = 
    [Product]@{
        Suite = "AzureADSync"
        Id = "AzureADSyncB2C"
        Name = "AzureADSyncB2C"
        DisplayName = "AzureADSyncB2C"
        Description = "Syncs Azure AD users to Azure AD B2C."
        Publisher = "Walker Analytics Consulting"
        HasTask = $true
        Installation = @{
            Prerequisite = @{
                Cloud = @("Azure")
                Product = @("AzureADCache")
                Provider = @("AzureAD")
                # Condition = @(
                #     $global:Azure.(Get-AzureTenantKeys).Tenant.Type -Contains "Azure AD B2C"
                # )
            }
        }
    }
}

$global:Catalog.Product += @{ StartRMTAgents = 
    [Product]@{
        Id = "StartRMTAgents"
        Name = "StartRMTAgents"
        DisplayName = "StartRMTAgents"
        Description = "Manages the restart of TableauRMT agents."
        Publisher = "Walker Analytics Consulting"
        HasTask = $true
        Installation = @{
            Prerequisite = @{
                Platform = @("TableauRMT")
                Provider = @("TableauServerTsmApi")
            }
        }
    }
}

$global:Catalog.Product += @{ AzureProjects = 
    [Product]@{
        Id = "AzureProjects"
        Name = "AzureProjects"
        DisplayName = "AzureProjects"
        Description = "Manages Azure project deployments."
        Publisher = "Walker Analytics Consulting"
        Log = "AzureProjects"
        Installation = @{
            Prerequisite = @{
                Cloud = @("Azure")
                Provider = @("AzureAD")
            }
        }
    }
}

$global:Catalog.Product += @{ AzureUpdateMgmt = 
    [Product]@{
        Id = "AzureUpdateMgmt"
        Name = "AzureUpdateMgmt"
        DisplayName = "Azure Update Management"
        Description = "Overwatch proxy for Microsoft Azure Automation Update Management."
        Publisher = "Walker Analytics Consulting"
        Installation = @{
            Prerequisite = @{
                Cloud = @("Azure")
            }
        }
    }
}

$global:Catalog.Product += @{ SSOMonitor = 
    [Product]@{
        Id = "SSOMonitor"
        Name = "SSOMonitor"
        DisplayName = "SSOMonitor"
        Description = "Monitors the ssoLogger on the Alteryx Server platform."
        Publisher = "Walker Analytics Consulting"
        Log = "SSOMonitor"
        HasTask = $true
        Installation = @{
            Prerequisite = @{
                Platform = @("AlteryxServer")
            }
        }
    }
}

$global:Catalog.Provider += @{ "OnePassword" = 
    [Provider]@{
        Id = "OnePassword"
        Name = "1Password"
        DisplayName = "Overwatch Provider for 1Password"
        Category = "Security"
        SubCategory = "Vault"
        Description = "Overwatch Provider for 1Password"
        Publisher = "Walker Analytics Consulting"
        Log = "OnePassword"
        Installation = @{
            Install = "scoop install 1password-cli"
            Uninstall = "scoop uninstall 1password-cli"
            Prerequisite = @{
                Installer = "scoop"
            }
        }
    }
}

$global:Catalog.Installer += @{ "scoop" = 
    [Installer]@{
        Id = "scoop"
        Name = "scoop"
        DisplayName = "scoop"
        Category = "Installer"
        Description = "A command-line installer for Windows"
        Publisher = "Luke Sampson"
        Installation = @{
            Prerequisite = @{
                OS = "WindowsServer"
            }
            Install = ". $($global:Location.Install)\install-scoop.ps1"
        }
    }
}

$global:Catalog.Provider += @{ SMTP = 
    [Provider]@{
        Id = "SMTP"
        Name = "SMTP"
        DisplayName = "SMTP"
        Category = "Messaging"
        Description = "Overwatch Provider for SMTP"
        Publisher = "Walker Analytics Consulting"
        Log = "SMTP"
        Installation = @{
            Prerequisite = @{
                PowerShell = @{
                    Package = @(
                        @{ Name = "Portable.BouncyCastle" },
                        @{ Name = "MimeKit" },
                        @{ Name = "MailKit" }
                    )
                }
            }
        }
    }
}

$global:Catalog.Provider += @{ TwilioSMS = 
    [Provider]@{
        Id = "TwilioSMS"
        Name = "Twilio SMS"
        DisplayName = "Twilio SMS"
        Category = "Messaging"
        Description = "Overwatch Provider for Twilio SMS"
        Publisher = "Walker Analytics Consulting"
        Log = "TwilioSMS"
        Installation = @{
            Prerequisite = @{}
        }
    }
}

$global:Catalog.Provider += @{ MicrosoftTeams = 
    [Provider]@{
        Id = "MicrosoftTeams"
        Name = "Microsoft Teams"
        DisplayName = "Microsoft Teams"
        Category = "Messaging"
        Description = "Overwatch Provider for Microsoft Teams"
        Publisher = "Walker Analytics Consulting"
        Log = "MicrosoftTeams"
        Installation = @{
            Prerequisite = @{}
        }
    }
}

$global:Catalog.Provider += @{ Views = 
    [Provider]@{
        Id = "Views"
        Name = "Views"
        DisplayName = "Views"
        Category = "Formatting"
        Description = "Property views for Overwatch objects."
        Publisher = "Walker Analytics Consulting"
        Installation = @{
            Flag = @("AlwaysInstall","UninstallProtected")
            Prerequisite = @{}
        }
    }
}

$global:Catalog.Provider += @{ Postgres = 
    [Provider]@{
        Id = "Postgres"
        Name = "Postgres"
        DisplayName = "Postgres"
        Category = "Database"
        Description = "Overwatch Provider for Postgres"
        Publisher = "Walker Analytics Consulting"
        Log = "Postgres"
        Installation = @{
            Prerequisite = @{
                Provider = @("ODBC")
                Driver = @("PostgreSQL Unicode(x64)")
            }
        }
    }
}

$global:Catalog.Driver += @{ "PostgreSQL Unicode(x64)" = 
    [Driver]@{
        Id = "PostgreSQL Unicode(x64)"
        Name = "PostgreSQL Unicode(x64)"
        DisplayName = "PostgreSQL Unicode(x64)"
        Category = "Database"
        DatabaseType = "PostgreSQL"
        DriverType = "ODBC"
        Publisher = "PostgreSQL Global Development Group"
        Version = @{
            Minimum = "12.02.00.00"
            AutoUpdate = $false
        }
        Platform = "64-bit"
        Installation = @{
            Flag = @("Manual")
            Prerequisite = @{
                Platform = @("TableauServer")
            }
        }
    }
    
}

$global:Catalog.Provider += @{ ODBC = 
    [Provider]@{
        Id = "ODBC"
        Name = "ODBC"
        DisplayName = "ODBC"
        Category = "Data Access"
        Description = "Overwatch Provider for ODBC"
        Publisher = "Walker Analytics Consulting"
        Log = "ODBC"
    }
}

$global:Catalog.Provider += @{ TableauServerWC = 
    [Provider]@{
        Id = "TableauServerWC"
        Name = "TableauServerWC"
        DisplayName = "Tableau Server Welcome Channel"
        Category = "Messaging"
        Description = "Overwatch Provider for Tableau Server Welcome Channel"
        Publisher = "Walker Analytics Consulting"
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
        Description = "Overwatch Provider for Okta"
        Publisher = "Walker Analytics Consulting"
        Log = "Okta"
        Installation = @{
            Prerequisite = @{}
        }
    }
}

$global:Catalog.Provider += @{ TableauServerRestApi = 
    [Provider]@{
        Id = "TableauServerRestApi"
        Name = "TableauServerRestApi"
        DisplayName = "Tableau Server REST API"
        Category = "TableauServer"
        Description = "Overwatch Provider for the Tableau Server REST API"
        Publisher = "Walker Analytics Consulting"
        Initialization = @{
            Api = @{
                Version = @{
                    Minimum = "3.15"
                    AutoUpdate = $true
                }
            }
            Prerequisite = @(
                @{ Type = "PlatformService"; PlatformService = "vizportal"; Status = "Running" }
            )
        }
        Installation = @{
            Prerequisite = @{
                Platform = @("TableauServer","TableauCloud")
            }
        }
    }
}

$global:Catalog.Provider += @{ TableauServerTsmApi = 
    [Provider]@{
        Id = "TableauServerTsmApi"
        Name = "TableauServerTsmApi"
        DisplayName = "Tableau Server TSM API"
        Category = "TableauServer"
        Description = "Overwatch Provider for the Tableau Server TSM API"
        Publisher = "Walker Analytics Consulting"
        Initialization = @{
            Api = @{
                Version = @{
                    Minimum = "0.5"
                    AutoUpdate = $true
                }
            }
            Prerequisite = @(
                @{ Type = "Service"; Service = "tabadmincontroller_0"; Status = "Running" }
            )
        }
        Installation = @{
            Prerequisite = @{
                Platform = @("TableauServer","TableauRMT")
            }
        }
    }
}

$global:Catalog.Provider += @{ TableauServerTabCmd = 
    [Provider]@{
        Id = "TableauServerTabCmd"
        Name = "TableauServerTabCmd"
        DisplayName = "Tableau Server TabCmd"
        Category = "TableauServer"
        Description = "Overwatch Provider for Tableau Server TabCmd"
        Publisher = "Walker Analytics Consulting" 
        Initialization = @{
            Prerequisite = @(
                @{ Type = "PlatformService"; PlatformService = "backgrounder"; Status = "Running" }
            )
        }
        Installation = @{
            Prerequisite = @{
                Platform = @("TableauServer","TableauCloud")
            }
        }
    }
}

$global:Catalog.Provider += @{ AzureAD =
    [Provider]@{
        Id = "AzureAD"
        Name = "AzureAD"
        DisplayName = "AzureAD"
        Description = "Overwatch Provider for Azure AD and Azure AD B2C."
        Publisher = "Walker Analytics Consulting"
        Installation = @{
            Prerequisite = @{
                Cloud = @("Azure")
            }
        }
    }
}