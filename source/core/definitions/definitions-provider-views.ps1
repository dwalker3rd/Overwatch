#region PROVIDER DEFINITIONS

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

$now = Get-Date

$Provider = $null
$Provider = $global:Catalog.Provider.Views

#endregion PROVIDER DEFINITIONS    
#region VIEW DEFINITIONS

$global:ViewSettings = @{
    MaxArrayElements = 1
    MaxStringLength = 100
}

$global:FileObjectView = @{
    Default = $([FileObject]@{}).PSObject.Properties.Name
    Min = @("Path","ComputerName",@{Name="Exists";Expression={$_.Exists}})
} 

$global:LogObjectView = @{
    Default = $([LogObject]@{}).PSObject.Properties.Name
    Min = @("Path","ComputerName")
} 

$global:CacheObjectView = @{
    Default = $([CacheObject]@{}).PSObject.Properties.Name
    Min = @("Path","ComputerName","MaxAge")
} 

$global:LogEntryView = @{
    Header = 'Index,TimeStamp,EntryType,Context,Action,"Target","Status","Message","Data"'
    Raw = @(
        "Index","TimeStamp","EntryType","Context","Action","Target","Status","Message","Data"
    )
    Default = @(
        "Index","TimeStamp","EntryType","Context","Action","Target","Status","Message"
    )
    Write = @(
        "Index",
        @{
            Name="TimeStamp"
            Expression = {
                (Get-Date($_.Timestamp)).ToString('u')
            }
        },
        "EntryType","Context","Action","Target","Status","Message","Data"
    )
    Formatted = @(
        "Index",
        @{
            Name="TimeStamp"
            Expression = {
                (Get-Date($_.Timestamp)).ToString('u')
            }
        },
        "EntryType","Context","Action",
        @{
            Name="Target"
            Expression = {
                ($_.Target.Substring(0,1) -eq "[") -and ($_.Target | ConvertFrom-Json).GetType().BaseType.Name -eq "Array" ? "$(($_.Target | ConvertFrom-Json) -join ",")" : $_.Target
                # ($_.Target.Substring(0,1) -eq "[") -and ($_.Target | ConvertFrom-Json).GetType().BaseType.Name -eq "Array" ? 
                #     (($_.Target | ConvertFrom-Json).Count -gt $global:ViewSettings.MaxArrayElements ? "$((($_.Target | ConvertFrom-Json)[0..($global:ViewSettings.MaxArrayElements-1)]) -join ","),..." : "$(($_.Target | ConvertFrom-Json) -join ",")") : 
                #     ($_.Target.Length -gt $global:ViewSettings.MaxStringLength ? "$($_.Target.Substring(0,($global:ViewSettings.MaxStringLength-1)))...}" : $_.Target)
            }
        },
        "Status","Message",
        # @{
        #     Name="Message"
        #     Expression = {
        #         ($_.Message.Length -gt $global:ViewSettings.MaxStringLength ? 
        #             ((Test-Json $_.Message) ? "$($_.Message.Substring(0,($global:ViewSettings.MaxStringLength-2)))...}" : "$($_.Message.Substring(0,($global:ViewSettings.MaxStringLength-1)))...") : 
        #             $_.Message)
        #     }
        # },
        "ComputerName"
    )
} 

$global:CimView = @{
    Default = $([PlatformCim]@{}).PSObject.Properties.Name
    Min = @("Id","Name","Status","Node","Required","Transient","IsOK","Class","ParentName","ParentId")
}

$global:UserView = @{
    Default = "*"
    Min = @("ComputerName","Name","Enabled","Groups")
}

$global:GroupView = @{
    Default = "*"
    Min = @("ComputerName","Name","Members")
}

$global:AzureView = @{
    User = @{
        Default = "*"
        Min = @("id","accountEnabled","displayName","mail","userPrincipalName")
        Plus = @(
            "id","accountEnabled","displayName","mail","userPrincipalName","groupMembership",
            @{Name="tenantId"; Expression = {$_.tenant.Id}},
            @{Name="tenantName"; Expression = {$_.tenant.Name}}
            )
        Membership = @{
            Default = "*"
            Min = @("id","displayName")
        }
    }
    Group = @{
        Default = @("id","displayName","securityEnabled","groupType","members")
        Plus = @(
            "id","displayName","securityEnabled","groupType","members",
            @{Name="tenantId"; Expression = {$_.tenant.Id}},
            @{Name="tenantName"; Expression = {$_.tenant.Name}}
            )
    }
}

$global:LicenseView = @{
    Default = @(
        @{
            Name="product"
            Expression = {
                if ($_.flowsEnabled) {"Data Management"} 
                elseif ($_.itmanagementBundleEnabled) {"System Management"} 
                elseif ($_.numCores -and $_.numCores -gt 0) {"Server Core"}
                elseif ($_.authorUserCount -and $_.authorUserCount -gt 0) {"Creator - Server"}
                elseif ($_.interactorUserCount -and $_.interactorUserCount -gt 0) {"Explorer - Server"}
                elseif ($_.basicUserCount -and $_.basicUserCount -gt 0) {"Viewer - Server"}
                else {"Unknown"}
            }
        },
        "serial",
        @{
            Name="numCores"
            Expression = {
                if ($_.flowsEnabled -and $_.numPrepCores -gt 0) {$_.numPrepCores} 
                elseif ($_.numCores -and $_.numCores -gt 0) {$_.numCores}
                else {0}
            }
        },
        @{
            Name="userCount"
            Expression = {
                if ($_.authorUserCount -and $_.authorUserCount -gt 0) {$_.authorUserCount}
                elseif ($_.interactorUserCount -and $_.interactorUserCount -gt 0) {$_.interactorUserCount}
                elseif ($_.basicUserCount -and $_.basicUserCount -gt 0) {$_.basicUserCount}
                else {0}
            }
        },
        "interactorUserCount","authorUserCount","basicUserCount","guestAllowed",
        "expiration","maintenance","valid","isActive","isUpdatable",
        @{Name="licenseExpired"; Expression = {$now -gt $_.expiration}},
        @{Name="licenseExpiry"; Expression = {$_.expiration - $now}},
        @{Name="maintenanceExpired"; Expression = {$now -gt $_.maintenance}},
        @{Name="maintenanceExpiry"; Expression = {$_.maintenance - $now}},
        "itmanagementBundleEnabled","flowsEnabled","backgrounderNodeRoleEnabled","filestoreNodeRoleEnabled","identityBasedActivationEnabled"
    )
    Report = @(
        @{
            Name="Product"
            Expression = {
                if ($_.flowsEnabled) {"Data Management"} 
                elseif ($_.itmanagementBundleEnabled) {"System Management"} 
                elseif ($_.numCores -and $_.numCores -gt 0) {"Server Core"}
                elseif ($_.authorUserCount -and $_.authorUserCount -gt 0) {"Creator - Server"}
                elseif ($_.interactorUserCount -and $_.interactorUserCount -gt 0) {"Explorer - Server"}
                elseif ($_.basicUserCount -and $_.basicUserCount -gt 0) {"Viewer - Server"}
                else {"Unknown"}
            }
        },
        @{Name="Key"; Expression = {$_.serial}},
        @{
            Name="Cores"
            Expression = {
                if ($_.flowsEnabled -and $_.numPrepCores -gt 0) {$_.numPrepCores} 
                elseif ($_.numCores -and $_.numCores -gt 0) {$_.numCores}
                else {0}
            }
        },
        @{
            Name="Users"
            Expression = {
                if ($_.authorUserCount -and $_.authorUserCount -gt 0) {$_.authorUserCount}
                elseif ($_.interactorUserCount -and $_.interactorUserCount -gt 0) {$_.interactorUserCount}
                elseif ($_.basicUserCount -and $_.basicUserCount -gt 0) {$_.basicUserCount}
                else {0}
            }
        },
        @{Name="Expiration"; Expression = {$_.expiration.ToString("u").Substring(0,10)}},
        @{Name="Maintenance"; Expression = {$_.maintenance.ToString("u").Substring(0,10)}},
        @{Name="Valid"; Expression = {$_.valid}},
        @{Name="Active"; Expression = {$_.isActive}},
        @{Name="Expired"; Expression = {$now -gt $_.expiration -or $now -gt $_.maintenance}}
    )
}
$global:LicenseView.Min = $global:LicenseView.Default


$global:TopologyView = @{
    NodeInfo = @(
        "NodeId", "Node", 
        @{Name="Cores"; Expression = {$_.ProcessorCount}},
        @{Name="Memory"; Expression = {"$([math]::Round($_.AvailableMemory/1000,0)) GB"}},
        @{Name="Storage"; Expression = {"$($_.TotalDiskSpace) GB"}}
    )
    Nodes = @("NodeId","Node")
    Raw = $($_.PSObject.Properties.Name)
}

$global:StatusView = @{
    Default = @("NodeId","Node","Status")
    Node = @("NodeId","Node","Status")
}

$global:PlatformJobView = @{
    Default = @("id","jobType","status","progress","createdAt","updatedAt","completedAt","statusMessage","jobTimeout","worker")
    Min = @(
        "id","jobType","status","progress",
        @{Name="doneSteps"; Expression = {$_.detailedProgress.doneSteps}},
        @{Name="totalSteps"; Expression = {$_.detailedProgress.totalSteps}},
        @{Name="createdAt"; Expression = {$epoch.AddSeconds($_.createdAt/1000).ToString("u")}},
        @{Name="updatedAt"; Expression = {$epoch.AddSeconds($_.updatedAt/1000).ToString("u")}},
        @{Name="completedAt"; Expression = {$epoch.AddSeconds($_.completedAt/1000).ToString("u")}},
        "statusMessage"
    )
    Watchlist = @(
        "id","status","progress",
        @{Name="updatedAt"; Expression = {$epoch.AddSeconds($_.updatedAt/1000).ToString("u")}},
        "context","callback"
    )
}

$global:UserMapView = @{
    Default = @(
        @{name="sourceUserId";expression={$_.sourceUser.Id}},
        @{name="sourceUserName";expression={$_.sourceUser.Name}},
        @{name="sourceUserSiteRole";expression={$_.sourceUser.siteRole}},
        @{name="azureADAccountEnabled";expression={$_.azureADUser.accountEnabled}},
        @{name="targetUserId";expression={$_.targetUser.Id}},
        @{name="targetUserName";expression={$_.targetUser.Name}},
        @{name="targetUserSiteRole";expression={$_.targetUser.siteRole}},
        @{name="idMatch";expression={$_.sourceUser.id -eq $_.targetUser.Id}} 
    )
    Basic = @(
        @{name="sourceUserId";expression={$_.sourceUser.Id}},
        @{name="sourceUserName";expression={$_.sourceUser.Name}},
        @{name="targetUserId";expression={$_.targetUser.Id}},
        @{name="targetUserName";expression={$_.targetUser.Name}},
        @{name="sourceUserSiteRole";expression={$_.sourceUser.siteRole}},
        @{name="azureADAccountEnabled";expression={$_.azureADUser.accountEnabled}},
        @{name="idMatch";expression={$_.sourceUser.id -eq $_.targetUser.Id}} 
    )
}

$global:PlatformEventView = @{
    Default = $([PlatformEvent]@{}).PSObject.Properties.Name
    Min = @("Event","EventStatus","EventReason","EventStatusTarget","EventCreatedBy","EventCreatedAt","EventUpdatedAt","EventCompletedAt","EventHasCompleted","ComputerName")
}

$global:CatalogView = @{
    CatalogObject = @{
        Default = ([CatalogObject]::new()).Properties() 
        Min = @("Type","Id","Name","DisplayName","Description","Publisher","Suite")
    }
    Overwatch = @{
        Default = ([Overwatch]::new()).Properties()
    }
    OS = @{
        Default = ([OS]::new()).Properties()
    }
    Cloud = @{
        Default = ([Cloud]::new()).Properties()
    }
    Platform = @{
        Default = ([Platform]::new()).Properties()
    }
    Product = @{
        Default = ([Product]::new()).Properties()
    }
    Provider = @{
        Default = ([Provider]::new()).Properties()
    }
}

#endregion VIEW DEFINITIONS

return $Provider