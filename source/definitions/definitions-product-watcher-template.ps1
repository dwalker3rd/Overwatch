#region PRODUCT DEFINITIONS

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $definitionsPath = $global:Location.Definitions
    . $definitionsPath\classes.ps1

    $global:Product = 
    [Product]@{
        Id = "Watcher"
        Name = "Watcher"
        Publisher = "Overwatch"
    }
    $global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
    $global:Product.TaskName = $global:Product.DisplayName
    $global:Product.Description = "Monitors CIM events for the $($global:Platform.Name) platform."
    $global:Product.HasTask = $false
    
    return $global:Product

#endregion PRODUCT DEFINITIONS