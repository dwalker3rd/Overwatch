$global:Catalog = @{}
$global:Catalog.Overwatch = @{}
$global:Catalog.Cloud = @{}
$global:Catalog.OS = @{}
$global:Catalog.Platform = @{}
$global:Catalog.Product = @{}
$global:Catalog.Provider = @{}
$global:Catalog.Installer = @{}
$global:Catalog.CLI = @{}

$global:Catalog.Overwatch += @{ Overwatch =  
    [Overwatch]@{
        Id = "Overwatch"
        Name = "Overwatch"
        DisplayName = "Overwatch"
        Description = ""
        Version = "2.1"
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
        Name = "Microsoft Windows Server"
        DisplayName = "Microsoft Windows Server"
        Image = "../img/windows_server.png"  
        Description = "Overwatch services for the Microsoft Windows Server operating system"
        Publisher = "Walker Analytics Consulting"
    }
}

$global:Catalog.OS += @{ Windows11 = 
    [OS]@{
        Id = "Windows11"
        Name = "Microsoft Windows 11"
        DisplayName = "Microsoft Windows 11"
        Image = "https://pathai4healthusers.z33.web.core.windows.net/Overwatch/img/windows_11.png" 
        Description = "Overwatch services for the Microsoft Windows 11 operating system"
        Publisher = "Walker Analytics Consulting"
    }
}

$_cloudAzurePowershellModules = @(
    @{ Name = "Az"; MinimumVersion = "11.0.0"; Repository = "PSGallery"; DoNotImport = $true }
    @{ Name = "Az.Accounts"; MinimumVersion = "2.13.2"},
    @{ Name = "Az.Compute"; MinimumVersion = "7.0.0" },
    @{ Name = "Az.Resources"; MinimumVersion = "6.12.0" },
    @{ Name = "Az.Storage"; MinimumVersion = "6.0.0" },
    @{ Name = "Az.Network"; MinimumVersion = "7.0.0" },
    @{ Name = "Az.CosmosDb"; MinimumVersion = "1.13.0" },
    @{ Name = "Az.SqlVirtualMachine"; MinimumVersion = "2.1.0" },
    @{ Name = "Az.KeyVault"; MinimumVersion = "5.0.0" },
    @{ Name = "Az.DataFactory"; MinimumVersion = "1.17.1" },
    @{ Name = "Az.Batch"; MinimumVersion = "3.5.0" }
)
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
            Prerequisites = @(
                @{
                    Type = "PowerShell"
                    PowerShell = @{
                        Modules = $_cloudAzurePowershellModules
                    }
                }
            )
        }
        Initialization = @{
            Prerequisites = @(
                @{
                    Type = "PowerShell"
                    PowerShell = @{
                        Modules = $_cloudAzurePowershellModules
                    }
                }
            )
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
        Installation = @{
            Flag = @("UnInstallable")
            PlatformInstanceId = @{
                Input = "None"
                Pattern = ""
                Replacement = ""
            }
        }
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
            IsInstalled = @(
                @{ Type = "Service"; Service = "tabadmincontroller_0" }
            )
            Prerequisites = @(
                @{ Type = "Provider"; Provider = "TableauServerRestApi"},
                @{ Type = "Provider"; Provider = "TableauServerTsmApi"},
                @{ Type = "Provider"; Provider = "TableauServerTabCmd"}
            )
            PlatformInstanceId = @{
                Input = "`$global:Platform.Uri.Host"
                Pattern = "\."
                Replacement = "-"
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
            Prerequisites = @(
                @{ Type = "Provider"; Provider = "TableauServerRestApi"},
                @{ Type = "Provider"; Provider = "TableauServerTabCmd"}
            )
            Flag = @("UnInstallable")
            PlatformInstanceId = @{
                Input = "`$global:Platform.Uri.Host"
                Pattern = "\."
                Replacement = "-"
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
        Initialization = @{
            Prerequisites = @(
                @{ Type = "Service"; Service = "TableauResourceMonitoringTool" },
                @{ Type = "Service"; Service = "TableauResourceMonitoringToolPostgreSQL" },
                @{ Type = "Service"; Service = "TableauResourceMonitoringToolRabbitMQ" }
            )
        }        
        Installation = @{
            IsInstalled = @(
                @{ Type = "Service"; Service = "TableauResourceMonitoringTool" }
            )
            Prerequisites = @(
                @{ Type = "Provider"; Provider = "TableauServerTsmApi"}
            )
            PlatformInstanceId = @{
                Input = "`$global:Platform.Uri.Host"
                Pattern = "\."
                Replacement = "-"
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
            Flags = @(
                "HasPlatformInstanceNodes"
            )
            UninstallString = [scriptblock]{
                return (Get-ItemProperty -Path (Invoke-Command $global:Catalog.Platform.AlteryxServer.Installation.RegistryKey.Uninstall) -Name UninstallString).UninstallString
            }
            InstallLocation = [scriptblock]{
                $uninstallString = Invoke-Command $global:Catalog.Platform.AlteryxServer.Installation.UninstallString
                return ([xml](Get-Content "$(Split-Path -Parent $uninstallString)\InstallInfo.xml")).Settings.InstallDir64
            }
            AlteryxEngineCmd = [scriptblock]{
                $installLocation = Invoke-Command $global:Catalog.Platform.AlteryxServer.Installation.InstallLocation
                return "$installLocation\AlteryxEngineCmd.exe"
            }
            RegistryKey = @{
                Uninstall = [scriptblock]{
                    foreach ($registryKey in (Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")) {
                        $displayName = (Get-ItemProperty -Path $registryKey.Name.Replace("HKEY_LOCAL_MACHINE","HKLM:") -Name DisplayName -ErrorAction SilentlyContinue).DisplayName
                        if ($displayName -like "Alteryx Server*") {
                            return $registryKey.Name.Replace("HKEY_LOCAL_MACHINE","HKLM:")
                        }
                    }}
                }
            IsInstalled = @(
                @{ Type = "Command"; Command = [scriptblock]{
                    try { . $global:Catalog.Platform.AlteryxServer.Installation.AlteryxEngineCmd *>$null; return $true } catch { return $false }
                }}
            )
            Build = [scriptblock]{
                return (Get-Item (Invoke-Command $global:Catalog.Platform.AlteryxServer.Installation.AlteryxEngineCmd)).VersionInfo.ProductVersion
            }
            Version = [scriptblock]{
                $build = (Invoke-Command $global:Catalog.Platform.AlteryxServer.Installation.Build)
                return [regex]::Matches($build,$global:RegexPattern.Software.Version)[0].Groups[1].Value
            }
            PlatformInstanceId = @{
                Input = "`$global:Platform.Uri.Host"
                Pattern = "\."
                Replacement = "-"
            }
            Python = @{
                Location = @{
                    Env = [scriptblock]{
                        $installLocation = Invoke-Command $global:Catalog.Platform.AlteryxServer.Installation.InstallLocation
                        return "$installLocation\\Miniconda3\envs\DesignerBaseTools_vEnv"
                    }
                    Pip = [scriptblock]{
                        $pythonEnvLocation = Invoke-Command $global:Catalog.Platform.AlteryxServer.Installation.Python.Location.Env
                        return "$pythonEnvLocation\Scripts"
                    }
                    SitePackages = [scriptblock]{
                        $pythonEnvLocation = Invoke-Command $global:Catalog.Platform.AlteryxServer.Installation.Python.Location.Env
                        return "$pythonEnvLocation\Lib\site-packages"
                    }
                }
            }
        }
    }
}

$global:Catalog.Platform += @{ AlteryxDesigner = 
    [Platform]@{
        Id = "AlteryxDesigner"
        Name = "Alteryx Designer"
        DisplayName = "Alteryx Designer"
        Image = "../img/alteryx_a_logo.png"
        Description = "Overwatch services for the Alteryx Designer platform"
        Publisher = "Walker Analytics Consulting"
        Installation = @{
            UninstallString = [scriptblock]{
                return (Get-ItemProperty -Path (Invoke-Command $global:Catalog.Platform.AlteryxDesigner.Installation.RegistryKey.Uninstall) -Name UninstallString).UninstallString
            }
            InstallLocation = [scriptblock]{
                $uninstallString = Invoke-Command $global:Catalog.Platform.AlteryxDesigner.Installation.UninstallString
                return ([xml](Get-Content "$(Split-Path -Parent $uninstallString)\InstallInfo.xml")).Settings.InstallDir64
            }
            AlteryxEngineCmd = [scriptblock]{
                $installLocation = Invoke-Command $global:Catalog.Platform.AlteryxDesigner.Installation.InstallLocation
                return "$installLocation\AlteryxEngineCmd.exe"
            }
            RegistryKey = @{
                Uninstall = [scriptblock]{
                    foreach ($registryKey in (Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")) {
                        $displayName = (Get-ItemProperty -Path $registryKey.Name.Replace("HKEY_LOCAL_MACHINE","HKLM:") -Name DisplayName -ErrorAction SilentlyContinue).DisplayName
                        if ($displayName -like "Alteryx Designer*") {
                            return $registryKey.Name.Replace("HKEY_LOCAL_MACHINE","HKLM:")
                        }
                    }}
                }
            IsInstalled = @(
                @{ Type = "Command"; Command = [scriptblock]{
                    try { . $global:Catalog.Platform.AlteryxDesigner.Installation.AlteryxEngineCmd *>$null; return $true } catch { return $false }
                }}
            )
            Build = [scriptblock]{
                return (Get-Item (Invoke-Command $global:Catalog.Platform.AlteryxDesigner.Installation.AlteryxEngineCmd)).VersionInfo.ProductVersion
            }
            Version = [scriptblock]{
                $build = Invoke-Command $global:Catalog.Platform.AlteryxDesigner.Installation.Build
                return [regex]::Matches($build,$global:RegexPattern.Software.Version)[0].Groups[1].Value
            }
            Flags = @(
                "NoPlatformInstanceUri","HasPlatformInstanceNodes"
            )
            PlatformInstanceId = @{
                Input = "`$env:COMPUTERNAME"
                Pattern = "\."
                Replacement = "-"
            }
            Python = @{
                Location = @{
                    Env = [scriptblock]{
                        $installLocation = Invoke-Command $global:Catalog.Platform.AlteryxDesigner.Installation.InstallLocation
                        return "$installLocation\Miniconda3\envs\DesignerBaseTools_vEnv"
                    }
                    Pip = [scriptblock]{
                        $pythonEnvLocation = Invoke-Command $global:Catalog.Platform.AlteryxDesigner.Installation.Python.Location.Env
                        return "$pythonEnvLocation\Scripts"
                    }
                    SitePackages = [scriptblock]{
                        $pythonEnvLocation = Invoke-Command $global:Catalog.Platform.AlteryxDesigner.Installation.Python.Location.Env
                        return "$pythonEnvLocation\Lib\site-packages"
                    }
                }
            }
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
            Prerequisites = @(
                @{ Type = "Platform"; Platform = @("TableauServer","AlteryxServer")}
            )
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
        Log = "AzureADSync"
        HasTask = $true
        Installation = @{
            Flag = @("NoPrompt")
            Prerequisites = @(
                @{ Type = "Cloud"; Cloud = "Azure"},
                @{ Type = "Provider"; Provider = "AzureAD"}
            )
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
        Log = "AzureADSync"
        HasTask = $true
        Installation = @{
            Prerequisites = @(
                @{ Type = "Platform"; Platform = "TableauServer"},
                @{ Type = "Product"; Product = "AzureADCache"},
                @{ Type = "Cloud"; Cloud = "Azure"},
                @{ Type = "Provider"; Provider = "AzureAD"}
            )
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
        Log = "AzureADSync"
        HasTask = $true
        Installation = @{
            Prerequisites = @(
                @{ Type = "Product"; Product = "AzureADCache"},
                @{ Type = "Cloud"; Cloud = "Azure"},
                @{ Type = "Provider"; Provider = "AzureAD"}
            )
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
            Prerequisites = @(
                @{ Type = "Platform"; Platform = "TableauRMT"},
                @{ Type = "Provider"; Provider = "TableauServerTsmApi"}
            )
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
            Prerequisites = @(
                @{ Type = "Cloud"; Cloud = "Azure"},
                @{ Type = "Provider"; Provider = "AzureAD"}
            )
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
            Prerequisites = @(
                @{ Type = "Cloud"; Cloud = "Azure"}
            )
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
            Prerequisites = @(
                @{ Type = "Platform"; Platform = "AlteryxServer"}
            )
        }
    }
}

$global:Catalog.Product += @{ AyxRunner = 
    [Product]@{
        Id = "AyxRunner"
        Name = "AyxRunner"
        DisplayName = "Alteryx Designer Runner"
        Description = "Monitors the Alteryx Designer Runner"
        Publisher = "Walker Analytics Consulting"
        HasTask = $true
        Installation = @{
            Prerequisites = @(
                @{ Type = "Platform"; Platform = "None"}
            )
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
        Initialization = @{
            Prerequisites = @(
                @{ 
                    CLI = "OnePasswordCLI"
                    Type = "CLI"
                }
            )
        }
        Installation = @{
            Prerequisites = @(
                @{ Type = "CLI"; CLI = "OnePasswordCLI" }
            )
            Flag = @("AlwaysLoad")
        }
    }
}

$global:Catalog.CLI += @{ "OnePasswordCLI" = 
    [CLI]@{
        Id = "OnePasswordCLI"
        Name = "1Password CLI"
        DisplayName = "1Password CLI"
        Category = "External"
        SubCategory = "CLI"
        Description = "1Password CLI"
        Publisher = "1Password"
        Installation = @{
            Install = [scriptblock]{scoop install 1password-cli --global *> $null}
            Update = [scriptblock]{scoop update 1password-cli --global *> $null}
            Uninstall = [scriptblock]{scoop uninstall 1password-cli --global *> $null}
            IsInstalled = @(
                @{ Type = "Command"; Command = [scriptblock]{try{op --version *> $null;$true}catch{$false}} }
            )
            Prerequisites = @(
                @{ Type = "Installer"; Installer = "scoop"}
            )
        }
    }
}

$global:Catalog.Installer += @{ "scoop" = 
    [Installer]@{
        Id = "scoop"
        Name = "scoop"
        DisplayName = "scoop"
        Category = "External"
        SubCategory = "Installer"
        Description = "A command-line installer for Windows"
        Publisher = "Luke Sampson"
        Uri = [uri]"https://scoop.sh/"
        Installation = @{
            IsInstalled = @(
                @{ Type = "Command"; Command = [scriptblock]{try{scoop update scoop *> $null;$true}catch{$false}} }
            )
            Prerequisites = @(
                @{ Type = "OS"; OS = @("WindowsServer","Windows11")}
            )
            Install = [scriptblock]{
                Invoke-RestMethod get.scoop.sh -outfile "$($global:Location.Temp)\install-scoop.ps1" *> $null
                . "$($global:Location.Temp)\install-scoop.ps1" -ScoopDir "$env:ProgramData\scoop"  -RunAsAdmin -scoopglobaldir "$env:ProgramData\scoop" *> $null
                $env:PATH = "$($env:ProgramData)\scoop\shims;" + $env:PATH
            }
            Uninstall = [scriptblock]{
                scoop uninstall scoop *> $null
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
        Description = "Overwatch Provider for SMTP"
        Publisher = "Walker Analytics Consulting"
        Log = "SMTP"
        Initialization = @{
            Prerequisites = @(
                @{
                    Type = "PowerShell"
                    PowerShell = @{
                        Packages = @(
                            @{ Name = "MimeKit"; RequiredVersion = "4.3.0"; ProviderName = "NuGet"; SkipDependencies = $true },
                            @{ Name = "MailKit"; RequiredVersion = "4.3.0"; ProviderName = "NuGet" }
                        )
                    }
                }
            )
        }
        Installation = @{
            Prerequisites = @(
                @{
                    Type = "PowerShell"
                    PowerShell = @{
                        Packages = @(
                            # @{ Name = "Portable.BouncyCastle"; RequiredVersion = "1.9.0"; ProviderName = "NuGet" },
                            @{ Name = "MimeKit"; RequiredVersion = "4.3.0"; ProviderName = "NuGet"; SkipDependencies = $true },
                            @{ Name = "MailKit"; RequiredVersion = "4.3.0"; ProviderName = "NuGet" }
                        )
                    }
                }
            )
            Flag = @("AlwaysLoad")
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
            Flag = @("AlwaysLoad")
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
            Flag = @("AlwaysLoad")
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
        # Installation = @{
        #     Prerequisites = @(
        #         @{ Type = "Driver"; Driver = "PostgreSQL"; DriverType = "ODBC"; BitVersion = "64-bit"}
        #     )
        # }
        # Initialization = @{
        #     Prerequisites = @(
        #         @{ Type = "Driver"; Driver = "PostgreSQL"; DriverType = "ODBC"; BitVersion = "64-bit"}
        #     )
        # }
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
            Prerequisites = @(
                @{ Type = "Platform"; Platform = "TableauServer"}
                @{ Type = "Provider"; Provider = "Postgres"}
            )
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
                Version = @{ Minimum = "3.15"; AutoUpdate = $true }
            }
            Prerequisites = @(
                @{ Type = "PlatformService"; PlatformService = "vizportal" }
            )
        }
        Installation = @{
            Prerequisites = @(
                @{ Type = "Platform"; Platform = @("TableauServer","TableauCloud")}
            )
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
                Version = @{ Minimum = "0.5"; AutoUpdate = $true }
            }
            Prerequisites = @(
                @{ Type = "Service"; Service = "tabadmincontroller_0" }             
            )
        }
        Installation = @{
            Prerequisites = @(
                @{ Type = "Platform"; Platform = @("TableauServer","TableauRMT")}
            )
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
        Installation = @{
            Prerequisites = @(
                @{ Type = "Platform"; Platform = @("TableauServer","TableauRMT")},
                @{ Type = "CLI"; CLI = "TableauServerTabCmdCLI"}
            )
        }
    }
}

$global:Catalog.CLI += @{ "TableauServerTabCmdCLI" = 
    [CLI]@{
        Id = "TableauServerTabCmdCLI"
        Name = "Tableau Server TabCmd CLI"
        DisplayName = "Tableau Server TabCmd CLI"
        Category = "External"
        SubCategory = "CLI"
        Description = "Tableau Server TabCmd CLI"
        Publisher = "Tableau Software, LLC"
        Installation = @{
            IsInstalled = @(
                @{ Type = "Command"; Command = [scriptblock]{try{tabcmd version *> $null;$true}catch{$false}} }
            )
            Prerequisites = @(
                @{ Type = "Platform"; Platform = @("TableauServer","TableauRMT")}
            )
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
            Prerequisites = @(
                @{
                    Type = "PowerShell"
                    PowerShell = @{
                        Modules = @(
                            @{ Name = "MSAL.PS"; MinimumVersion = "4.37.0.0" }
                        )
                    }
                }
                @{ Type = "Cloud"; Cloud = "Azure"}
            )
        }
        Initialization = @{
            Prerequisites = @(
                @{
                    Type = "PowerShell"
                    PowerShell = @{
                        Modules = @(
                            @{ Name = "MSAL.PS"; MinimumVersion = "4.37.0.0" }
                        )
                    }
                }
                @{ Type = "Cloud"; Cloud = "Azure"}
            )
        }
    }
}
