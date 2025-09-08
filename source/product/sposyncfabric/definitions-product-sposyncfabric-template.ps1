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

    $global:Product.Config = @{}

    $global:SharePoint = @{
        Tenant = "<SharePoint Tenant>"
        Site = "<SharePoint Site>"
        List = @{
            Workspaces = "Fabric Workspaces"
            Capacities = "Fabric Capacities"
            Users = "Fabric Users"
            Groups = "Fabric Groups"
            GroupMembership = "Fabric Group Membership"
            WorkspaceRoleAssignments = "Fabric Workspace Role Assignments"
            IncludeColumns = @("Created", "Modified")
            ExcludeColumns = @("Title", "Attachments")        
        }
        ListItem = @{
            StatusExpiry = 30
        }
    }

    $global:Fabric = @{
        Tenant = "<Fabric Tenant>"
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

    return $global:Product

#endregion PRODUCT DEFINITIONS