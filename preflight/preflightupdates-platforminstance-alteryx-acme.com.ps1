#region PREFLIGHT

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    # if Alteryx Server was upgraded, force read of platform info
    Clear-Cache platforminfo
    
    # confirm that the AlteryxService service is configured to run as AlteryxSVC
    $secUpdates += Set-ServiceSecurity AlteryxService -ComputerName (Get-PlatformTopology nodes -Keys) 
    if ($secUpdates) {
        Write-Host+ -NoTrace "Service security changes were applied." -ForegroundColor Yellow
        Write-Host+ -NoTrace "Restart platform ASAP." -ForegroundColor Yellow
    }

    # ensure that the AlteryxService service is disabled for offline nodes
    $standbyNodes = foreach ($component in (pt components -k)) {pt components.$component.Standby}
    Set-PlatformService -Name "AlteryxService" -StartupType "Disabled" -Computername $standbyNodes

    # confirm that the required crypto/ssl files are in the DLLs directory
    # see https://github.com/conda/conda/issues/8273
    Repair-PythonSSL -ComputerName (Get-PlatformTopology nodes -keys)

    # confirm that these python packages have been installed
    # these packages are in addition to those installed by Alteryx
    $requiredPythonPackages = @('tableauserverclient','tableauhyperapi','shapely')
    Install-PythonPackage -Package $requiredPythonPackages -Pip $global:Location.Pip -ComputerName (Get-PlatformTopology nodes -keys)

    Edit-Files -Path "F:\Program Files\Alteryx\bin\HtmlPlugins\PublishToTableauServer_v2.0.0\Supporting_Macros\PublishToTableauServer.yxmc" -Find "HTTP\/1\.1\s201\sCreated" -Replace "HTTP\1.1 201" 
    Copy-Files -Path "F:\Program Files\Alteryx\bin\HtmlPlugins\PublishToTableauServer_v2.0.0\Supporting_Macros\PublishToTableauServer.yxmc" -ComputerName (Get-PlatformTopology nodes -Keys)  -ExcludeComputerName $env:COMPUTERNAME

    # enable powershell 'double-hop' with credssp on controller
    Enable-CredSspDoubleHop -ComputerName (pt components.controller.nodes -k)

#endregion PREFLIGHT