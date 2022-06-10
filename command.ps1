#Requires -RunAsAdministrator
#Requires -Version 7

[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

param(
    [Parameter(Mandatory=$false,Position=0)][string]$Command,
    [Parameter(Mandatory=$false)][string]$OverwatchController = $env:COMPUTERNAME,
    # [Parameter(Mandatory=$false)][string]$ComputerName,
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
$global:PreflightPreference = $SkipPreflight ? "SilentlyContinue" : "Continue"
$global:PostflightPreference = $SkipPreflight ? "SilentlyContinue" : "Continue"
$global:WriteHostPlusPreference = "SilentlyContinue"

# product id must be set before include files
$global:Product = @{Id="Command"}
. $PSScriptRoot\definitions.ps1

$global:WriteHostPlusPreference = "Continue"

$result = $null
if ($Command) {

    if (!$NoDoubleHop -and $Context -like "Azure*" -and $Platform.Id -in ("AlteryxServer","TableauRMT")) {
        $DoubleHop = $true
    }

    if ($DoubleHop) {

        Write-Host+ -NoTrace "Remoting to $OverwatchController using CredSSP `"double hop`"." 

        $creds = Get-Credentials "localadmin-$($Platform.Instance)"
        if ($creds.UserName -notlike ".\*" -and $creds.UserName -notlike "$OverwatchController\*" -and $creds.UserName -notlike "$($global:Platform.Domain)\*") {
            Write-Host+ -NoTrace "ERROR: Credentials must include the NETBIOS or domain name in the username when remoting with CredSSP." -ForegroundColor DarkRED
            if ($global:PrincipalContextType -eq [System.DirectoryServices.AccountManagement.ContextType]::Machine) {
                Write-Host+ -NoTrace "ATTENTION: Modifying the username in the credentials to include the NETBIOS name and continuing." 
                $creds = Request-Credentials -UserName ".\$($creds.UserName)" -Password $creds.GetNetworkCredential().Password
            }
            elseif ($global:PrincipalContextType -eq [System.DirectoryServices.AccountManagement.ContextType]::Domain) {
                Write-Host+ -NoTrace "ATTENTION: Modifying the username in the credentials to include the domain name and continuing." 
                $creds = Request-Credentials -UserName "$($global:Platform.Domain)\$($creds.UserName)" -Password $creds.GetNetworkCredential().Password
            }
            # else {
            #     Write-Host+ -NoTrace "ERROR: Username must include the NETBIOS or domain name when remoting with CredSSP." -ForegroundColor Red
            #     return
            # }
        }

        $workingDirectory = $global:Location.Root
        $result = Invoke-Command -ComputerName $OverwatchController `
            -ScriptBlock {
                    Set-Location $using:workingDirectory; 
                    pwsh command.ps1 -Command $using:Command -Context $using:Context -Reason $using:Reason -NoDoubleHop -SkipPreflight
                } `
            -Authentication Credssp `
            -Credential $creds 
            
        return $result

    }
    else {

        $commandExpression = $Command
        $commandParametersKeys = (Get-Command $Command.Split(" ")[0]).parameters.keys
        
        # if (![string]::IsNullOrEmpty($ComputerName) -and $commandParametersKeys -contains "ComputerName") {$commandExpression += " -ComputerName $ComputerName"}
        if (![string]::IsNullOrEmpty($Context) -and $commandParametersKeys -contains "Context") {$commandExpression += " -Context '$Context'"}
        if (![string]::IsNullOrEmpty($Reason) -and $commandParametersKeys -contains "Reason") {$commandExpression += " -Reason '$Reason'"}
        if (![string]::IsNullOrEmpty($RunId) -and $commandParametersKeys -contains "RunId") {$commandExpression += " -RunId '$RunId'"}
        
        Write-Host+ -NoTrace "Overwatch controller: $OverwatchController"
        Write-Host+ -NoTrace "Command: $commandExpression" 
        Write-Host+
        
        $result = Invoke-Expression -Command $commandExpression
        return $result

    }

}