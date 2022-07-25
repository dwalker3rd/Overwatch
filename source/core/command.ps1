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
    [switch]$Credssp,
    [Parameter(Mandatory=$false)][string]$Context,
    [Parameter(Mandatory=$false)][string]$Reason,
    [Parameter(Mandatory=$false)][string]$RunId
)

function Test-Runbook { 
    Write-Host+ "[Test-Runbook] PENDING "
    Write-Host+ "[Test-Runbook] Test-PsRemoting: PENDING"
    Test-PsRemoting
    Write-Host+ "[Test-Runbook] Test-PsRemoting: FINISHED"
    Write-Host+ "[Test-Runbook] FINISHED"
}

$global:UseCredssp = $false
if ($Credssp) {
    $global:UseCredssp = $true
}

$result = $null
if ($Command) {

    if (!$NoDoubleHop -and $Context -like "Azure*") { # -and $Platform.Id -in ("AlteryxServer","TableauRMT")) {
        $DoubleHop = $true
        $global:UseCredssp = $true
    }

    if ($DoubleHop) {

        $SkipPreflight = $true

        $global:DebugPreference = "SilentlyContinue"
        $global:InformationPreference = "SilentlyContinue"
        $global:VerbosePreference = "SilentlyContinue"
        $global:WarningPreference = "Continue"
        $global:ProgressPreference = "SilentlyContinue"
        $global:PreflightPreference = $SkipPreflight ? "SilentlyContinue" : "Continue"
        $global:PostflightPreference = $SkipPreflight ? "SilentlyContinue" : "Continue"
        $global:WriteHostPlusPreference = "Continue"

        # product id must be set before include files
        $global:Product = @{Id="Command"}
        . $PSScriptRoot\definitions.ps1

        # $global:WriteHostPlusPreference = "Continue"

        Write-Host+ -NoTrace "Remoting to $OverwatchController using CredSSP `"double hop`"." 

        $creds = Get-Credentials "localadmin-$($Platform.Instance)" -Credssp

        $workingDirectory = $global:Location.Root
        $result = Invoke-Command -ComputerName $OverwatchController `
            -ScriptBlock {
                    Set-Location $using:workingDirectory; 
                    pwsh command.ps1 -Command $using:Command -Context $using:Context -Reason $using:Reason -NoDoubleHop -Credssp -SkipPreflight
                } `
            -Authentication Credssp `
            -Credential $creds 
            
        return $result

    }
    else {

        $global:DebugPreference = "SilentlyContinue"
        $global:InformationPreference = "SilentlyContinue"
        $global:VerbosePreference = "SilentlyContinue"
        $global:WarningPreference = "Continue"
        $global:ProgressPreference = "SilentlyContinue"
        $global:PreflightPreference = $SkipPreflight ? "SilentlyContinue" : "Continue"
        $global:PostflightPreference = $SkipPreflight ? "SilentlyContinue" : "Continue"
        $global:WriteHostPlusPreference = "Continue"

        # product id must be set before include files
        $global:Product = @{Id="Command"}
        . $PSScriptRoot\definitions.ps1

        # $global:WriteHostPlusPreference = "Continue"

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