#region PRODUCT DEFINITIONS

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $definitionsPath = $global:Location.Definitions
    . $definitionsPath\classes.ps1

    $global:Product = $global:Catalog.Product.Command
    $global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.DisplayName)"
    $global:Product.TaskName = $global:Product.DisplayName
    $global:Product.Description = "A command interface for managing the $($global:Platform.DisplayName) platform."
    $global:Product.ShutdownMax = New-TimeSpan -Minutes 5
    $global:Product.HasTask = $false

    return $global:Product

#endregion PRODUCT DEFINITIONS