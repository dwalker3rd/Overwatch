param(
    [Parameter(Mandatory=$false)][string]$ComputerName 
)

$isPlatformInstance = [string]::IsNullOrEmpty($ComputerName)
$isPlatformInstanceNode = !$isPlatformInstance

#region PREFLIGHT

    if ($isPlatformInstance) {

        # if Alteryx Server was upgraded, clear platforminfo cache
        # platforminfo will then be reloaded on next init
        Clear-Cache platforminfo
        
    }
    
    if ($isPlatformInstanceNode) {

        # confirm that the AlteryxService service is configured with run as account
        # the run as account and credentials are stored in the vault under "AlteryxService" 
        $secUpdates += Set-ServiceSecurity AlteryxService -ComputerName $ComputerName
        if ($secUpdates) {
            Write-Host+ -NoTrace "Service security changes were applied." -ForegroundColor Yellow
            Write-Host+ -Iff $isPlatformInstance -NoTrace "Restart platform ASAP." -ForegroundColor Yellow
        }

        # confirm that the required crypto/ssl files are in the DLLs directory
        # see https://github.com/conda/conda/issues/8273
        Repair-PythonSSL -ComputerName $ComputerName

        # install any additional python packages required for your Alteryx Server environment
        # these are in addition to those python packages installed by Alteryx Server
        if ($requiredPythonPackages) {
            Install-PythonPackage -Package $requiredPythonPackages -Pip $global:Location.Python.Pip -ComputerName $ComputerName -Upgrade -UpgradeStrategy "only-if-needed" -Quiet
        }
    }

    if ($isPlatformInstance -or $ComputerName -eq (pt components.controller.nodes -k)) {
        # enable powershell 'double-hop' with credssp on controller
        Enable-CredSspDoubleHop -ComputerName (pt components.controller.nodes -k)
    }

#endregion PREFLIGHT