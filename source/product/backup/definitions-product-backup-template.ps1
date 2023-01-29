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

    $global:Product = $global:Catalog.Product.Backup
    $global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
    $global:Product.TaskName = $global:Product.DisplayName
    $global:Product.Description = "Manages backups for the $($global:Platform.Name) platform."
    $global:Product.ShutdownMax = New-TimeSpan -Minutes 15
    $global:Product.HasTask = $true

    $global:Product.Config = @{}
    $global:Product.Config += @{
        Backup = @{
            Path = "<backupArchiveLocation>"
            Name = "$($global:Environ.Instance).$(Get-Date -Format 'yyyyMMddHHmm')"
            Extension = "bak"
            MaxRunTime = New-Timespan -Minutes 15
        }
    }

    return $global:Product

#endregion PRODUCT DEFINITIONS