#region PROVIDER DEFINITIONS

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $definitionsPath = $global:Location.Definitions
    . $definitionsPath\classes.ps1

    $Provider = $null
    $Provider = [Provider]@{
        Id = "Vault"
        Name = "Vault"
        DisplayName = "Vault"
        Category = "Security"
        SubCategory = "Vault"
        Description = "Default vault provider"
        Log = "$($global:Location.Logs)\$($Provider.Id).log"
        Vendor = "Overwatch"
    }

    $Provider.Config = @{}

    return $Provider

#endregion PROVIDER DEFINITIONS