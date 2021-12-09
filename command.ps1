#Requires -RunAsAdministrator
#Requires -Version 7

param(
    [Parameter(Mandatory=$false,Position=0)][string]$Command,
    [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
    [switch]$RunSilent,
    [switch]$DoubleHop,
    [switch]$NoDoubleHop,
    [switch]$SkipPreflight,
    [Parameter(Mandatory=$false)][string]$Context,
    [Parameter(Mandatory=$false)][string]$Reason,
    [Parameter(Mandatory=$false)][string]$RunId
)

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "SilentlyContinue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"
$global:WriteHostPlusPreference = "SilentlyContinue"

# product id must be set before include files
$global:Product = @{Id="Command"}
. $PSScriptRoot\definitions.ps1

$global:WriteHostPlusPreference = "Continue"

$result = $null
if ($Command) {

    if (!$NoDoubleHop -and $Context -like "Azure*" -and $Platform.Id -eq "AlteryxServer") {
        $DoubleHop = $true
    }

    if ($DoubleHop) {

        Write-Host+ -NoTrace "Remoting to $ComputerName using CredSSP `"double hop`"." 

        $creds = Get-Credentials "localadmin-$($Platform.Instance)"
        if ($creds.UserName -notlike ".\*" -and $creds.UserName -notlike "$ComputerName\*") {
            Write-Host+ -NoTrace "ERROR: Username must include the NETBIOS or domains name when remoting with CredSSP." -ForegroundColor Red
            return
        }

        $result = Invoke-Command -Authentication CredSsp `
            -ScriptBlock {
                    Set-Location F:\Overwatch; 
                    pwsh command.ps1 -Command $using:Command -Context $using:Context -Reason $using:Reason -NoDoubleHop -SkipPreflight -RunSilent
                } `
            -ComputerName $ComputerName `
            -Credential $creds
        
            return $result

    }
    else {

        $commandParams = (Get-Command $Command).parameters.keys
        
        $commandExpression = $Command
        if (![string]::IsNullOrEmpty($Context) -and $commandParams -contains "Context") {$commandExpression += " -Context '$Context'"}
        if (![string]::IsNullOrEmpty($Reason) -and $commandParams -contains "Reason") {$commandExpression += " -Reason '$Reason'"}
        if (![string]::IsNullOrEmpty($RunId) -and $commandParams -contains "RunId") {$commandExpression += " -RunId '$RunId'"}
        
        Write-Host+ -NoTrace "Executing `"$commandExpression`" on $ComputerName" 
        Write-Host+
        
        $result = Invoke-Expression -Command $commandExpression
        return $result

    }

}

return

