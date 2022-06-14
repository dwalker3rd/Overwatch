﻿#region PRODUCT DEFINITIONS

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $definitionsPath = $global:Location.Definitions
    . $definitionsPath\classes.ps1

    $global:Product = 
    [Product]@{
        Id = "Cleanup"
        Name = "Cleanup"
        Publisher = "Overwatch"
    }
    $global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
    $global:Product.TaskName = $global:Product.DisplayName
    $global:Product.Description = "Manages file and data assets for the $($global:Platform.Name) platform."
    $global:Product.HasTask = $true

    return $global:Product

#endregion PRODUCT DEFINITIONS