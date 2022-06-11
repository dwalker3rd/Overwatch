#region PRODUCT DEFINITIONS

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $definitionsPath = $global:Location.Definitions
    . $definitionsPath\classes.ps1

    $global:Product = 
        [Product]@{
            Id = "DiskCheck"
            Name = "DiskCheck"
            Publisher = "Overwatch"
        }
    $global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
    $global:Product.TaskName = $global:Product.DisplayName
    $global:Product.Description = "Monitors storage devices critical to the $($global:Platform.Name) platform."
    $global:Product.HasTask = $true
    
    $global:imgDisk = "$($global:Location.Images)/disk.png"
    $global:imgDiskSpaceLow = "$($global:Location.Images)/diskspace_low.png"

    return $global:Product

#endregion PRODUCT DEFINITIONS