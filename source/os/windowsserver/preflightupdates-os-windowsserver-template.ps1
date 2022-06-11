#region PREFLIGHT

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    Update-GroupPolicy -ComputerName (pt nodes -k) -Update

#endregion PREFLIGHT