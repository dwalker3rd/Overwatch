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

if (!$MinimumDefinitions) {

    $azVmContext = Get-AzVmContext
    $azVmExtension = Get-AzVMExtension -ResourceGroupName $azVmContext.ResourceGroupName -VMName $env:COMPUTERNAME -Name $global:Product.Id

    $global:Product.Config = @{}
    $global:Product.Config += @{
        Extension = $azVmExtension
        Registry = @{
            Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
            Key = "BGInfo"
        }
        Location = @{
            Data = "$($global:Location.Data)\bgInfo"
            Plugins = "C:\Packages\Plugins"
        }
    }
    $global:Product.Config.Location += @{ 
        VmExtension = "$($global:Product.Config.Location.Plugins)\$($azVmExtension.Publisher).$($azVmExtension.ExtensionType)\$($azVmExtension.TypeHandlerVersion)" 
    }
    $global:Product.Config.Location += @{
        Files = @{
            Destination = @{
                ConfigBgi = "$($global:Product.Config.Location.VmExtension)\config.bgi"
                ConfigTxt = "$($global:Product.Config.Location.VmExtension)\config.txt"
            }
            Source = @{
                ConfigBgi = "$($global:Product.Config.Location.Data)\config.bgi"
            }
        }
    }
    $global:Product.Config += @{
        CommandLine = @{
            Executable = "$($global:Product.Config.Location.VmExtension)\bgInfo.exe"
            Options = @("/nolicprompt","/timer:0")
        }
    }

}

return $global:Product

#endregion PRODUCT DEFINITIONS