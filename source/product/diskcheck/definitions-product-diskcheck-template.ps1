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

    $global:Product = $global:Catalog.Product.DiskCheck
    $global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
    $global:Product.TaskName = $global:Product.DisplayName
    $global:Product.Description = "Monitors storage devices critical to the $($global:Platform.Name) platform."
    $global:Product.HasTask = $true
    
    $global:imgDisk = "$($global:Location.Images)/disk.png"
    $global:imgDiskSpaceLow = "$($global:Location.Images)/diskspace_low.png"

    return $global:Product

#endregion PRODUCT DEFINITIONS