param(
    [Parameter(Mandatory=$false)][string]$ComputerName 
)

$isPlatformInstance = [string]::IsNullOrEmpty($ComputerName)
$isPlatformInstanceNode = !$isPlatformInstance

#region PREFLIGHT
    
    if ($isPlatformInstanceNode) {

        # ensure that node is reachable via network and psremoting
        # if these fail, do not continue
        if ((Test-NetConnection+ -ComputerName $ComputerName).Result -contains "Fail") {
            throw "Node $($ComputerName) failed network tests"
        }
        if ((Test-PSRemoting -ComputerName $ComputerName).Result -contains "Fail") {
            throw "Node $($ComputerName) failed PowerShell remoting tests"
        }

    }

#endregion PREFLIGHT