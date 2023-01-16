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

    $global:Product = $global:Catalog.Product.BgInfo
    $global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
    $global:Product.TaskName = $global:Product.DisplayName

    $azVmContext = Get-AzVmContext
    $_x = Get-AzVMExtension -ResourceGroupName $azVmContext.ResourceGroupName -VMName $env:COMPUTERNAME -Name $global:Product.Id

    $global:Product.Config = @{}
    $global:Product.Config += @{
        Extension = $_x
        Registry = @{
            Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
            Key = "BGInfo"
        }
        Location = @{
            Data = "$($global:Location.Data)\bgInfo"
            Extension = "C:\Packages\Plugins"
        }

    }
    $_c = $global:Product.Config
    $_l = $_c.Location
    $global:Product.Config += @{
        Config = "$($_l.Data)\bgInfo.bgi"
        Content = "$($_l.Data)\bgInfo.txt"
        Executable = "$($_l.Extension)\$($_x.Publisher).$($_x.ExtensionType)\$($_x.TypeHandlerVersion)\bgInfo.exe"
    }

    return $global:Product

#endregion PRODUCT DEFINITIONS