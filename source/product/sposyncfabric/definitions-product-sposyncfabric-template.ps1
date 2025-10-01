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
            StatusExpiry = New-Timespan -Minutes 5
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
