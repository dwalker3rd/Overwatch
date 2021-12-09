﻿#region PRODUCT DEFINITIONS

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $definitionsPath = $global:Location.Definitions
    . $definitionsPath\classes.ps1

    $global:Product = 
    [Product]@{
        Id = "Command"
        Name = "Command"
        Vendor = "Overwatch"
    }
    $global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
    $global:Product.TaskName = $global:Product.DisplayName
    $global:Product.Description = "A command interface for managing the $($global:Platform.Name) platform."
    $global:Product.ShutdownMax = New-TimeSpan -Minutes 5
    $global:Product.HasTask = $false

    return $global:Product

#endregion PRODUCT DEFINITIONS