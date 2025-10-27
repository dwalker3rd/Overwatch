#region PRODUCT DEFINITIONS

    param(
        [switch]$MinimumDefinitions
    )

    if ($MinimumDefinitions) {
        $root = $PSScriptRoot -replace "\\definitions",""
        Invoke-Command  -ScriptBlock { . $root\definitions.ps1 -MinimumDefinitions }
    }
    else {
        . $PSScriptRoot\classes.ps1
    }

    $global:Product = $global:Catalog.Product.SPOSyncFabric

    $global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name)"
    $global:Product.DisplayName += $global:Platform.Name -ne "None" ?  "for $($global:Platform.Name)" : $null
    $global:Product.TaskName = $global:Product.DisplayName
    $global:Product.Description = "Syncs SharePoint lists to Microsoft Fabric objects."
    $global:Product.HasTask = $true

    $global:Product.Config = @{}

    $global:SharePoint = @{
        Tenant = "pathseattle"
        Site = "rhsupplies"
        List = @{
            Workspaces = @{
                Name = "Fabric Workspaces"
            }
            Capacities = @{
                Name = "Fabric Capacities"
            }
            Users = @{
                Name = "Fabric Users"
                ShowAcceptedExpiry = New-TimeSpan -Days 3
            }
            Groups = @{
                Name = "Fabric Groups"
            }
            GroupMembership = @{
                Name = "Fabric Group Membership"
            }
            WorkspaceRoleAssignments = @{
                Name = "Fabric Workspace Role Assignments"
            }
            Log = @{
                Name = "Fabric Automation Log"
            }   
            AutoProvisioning = @{
                GroupsAndRoles = @{
                    Name = "Auto-Provisioning Template for Groups and Roles"
                }
            }                      
            IncludeColumns = @("Created", "Modified")
            ExcludeColumns = @("Title", "Attachments")        
        }
        ListItem = @{
            StatusExpiry = New-Timespan -Minutes 65
        }
    }

    $global:Fabric = @{
        Tenant = "rhsuppliesdata"
        Capacities = @{
            Special = @(
                    "Trial*", 
                    "Premium Per User*"
            )
        }
        Workspaces = @{
            Applications = @(
                "Microsoft Fabric Release Plan", 
                "Microsoft Fabric Capacity Metrics", 
                "Microsoft Fabric Chargeback Reporting"
            )
        }
    }

    $global:ExchangeOnline = @{
        Tenant = "rhsuppliesdata"
    }

    return $global:Product

#endregion PRODUCT DEFINITIONS
