#region PRODUCT DEFINITIONS

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $definitionsPath = $global:Location.Definitions
    . $definitionsPath\classes.ps1

    $global:Product = $global:Catalog.Product.Backup
    $global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
    $global:Product.TaskName = $global:Product.DisplayName
    $global:Product.Description = "Manages backups for the $($global:Platform.Name) platform."
    $global:Product.ShutdownMax = New-TimeSpan -Minutes 15
    $global:Product.HasTask = $true

    return $global:Product

#endregion PRODUCT DEFINITIONS