#Requires -RunAsAdministrator
#Requires -Version 7

[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

param(
    [Parameter(Mandatory=$false,Position=0)][string]$Command,
    [Parameter(Mandatory=$false)][string]$OverwatchController = $env:COMPUTERNAME,
    [switch]$NoDoubleHop,
    [switch]$Credssp,
    # [Parameter(Mandatory=$false)][string]$Context,
    [Parameter(Mandatory=$false)][string]$Reason,
    [Parameter(Mandatory=$false)][string]$RunId
)

[Flags()] enum AzureUpdateMgmtFlags {
    None = 0
    DisableMessaging = 1
    DisableMessagingWithTimeout = 2
    ReenableMessaging = 4
    ReenableMessagingWithDelay = 8
}

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "SilentlyContinue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"
$global:WriteHostPlusPreference = "Continue"

$global:DisableConsoleSequences = $true

$global:UseCredssp = $false
if ($Credssp) {
    $global:UseCredssp = $true
}

$Command = (Get-Culture).TextInfo.ToTitleCase($Command)
$Reason = ![string]::IsNullOrEmpty($Reason) -and $Reason -ne "None"  ? $Reason : $null

$azureUpdateMgmtFlags = 
    switch ($Command) {
        "Stop-Platform" { [AzureUpdateMgmtFlags]::DisableMessaging }
        "Start-Platform" { [AzureUpdateMgmtFlags]::ReenableMessagingWithDelay }
        default { [AzureUpdateMgmtFlags]::None }
    }

$result = $null
if ($Command) {

    if (!$NoDoubleHop) {

        $global:UseCredssp = $true

        # product id must be set before include files
        $global:Product = @{Id="AzureUpdateMgmt"}
        . $PSScriptRoot\definitions.ps1

        Send-AzureUpdateMgmtMessage -Command $Command -Reason $Reason -Status Starting      

        $action = "Remoting to $OverwatchController using CredSSP"; $status = "Start"; $message = "$($action): $status" 
        Write-Log -Action $action -Target $Command -Status $status -Message $message
        Write-Host+ -NoTrace $message 

        if ($azureUpdateMgmtFlags.HasFlag([AzureUpdateMgmtFlags]::DisableMessaging)) {
            Disable-Messaging -Duration ([timespan]::MaxValue)
        }
        if ($azureUpdateMgmtFlags.HasFlag([AzureUpdateMgmtFlags]::DisableMessagingWithTimeout)) {
            Disable-Messaging -Duration $global:PlatformMessageDisabledTimeout
        }

        $creds = Get-Credentials "localadmin-$($global:Platform.Instance)" -LocalMachine

        $workingDirectory = $global:Location.Root
        $result = Invoke-Command -ComputerName $OverwatchController `
            -ScriptBlock {
                    Set-Location $using:workingDirectory; 
                    pwsh azureupdatemgmt.ps1 -Command $using:Command -Reason $using:Reason -NoDoubleHop -CredSSP
                } `
            -Authentication Credssp `
            -Credential $creds 

        $action = "Remoting to $OverwatchController using CredSSP"; $status = "Completed"; $message = "$($action): $status" 
        Write-Log -Action $action -Target $Command -Status $status -Message $message
        Write-Host+ -NoTrace $message         

    }
    else {

        $global:WriteHostPlusPreference = "SilentlyContinue"

        # product id must be set before include files
        $global:Product = @{Id="AzureUpdateMgmt"}
        . $PSScriptRoot\definitions.ps1

        $global:WriteHostPlusPreference = "Continue"

        $action = "Execute"; $status = "Start"; $message = "$action $($Command): $status" 
        Write-Log -Action $action -Target $Command -Status $status -Message $message
        Write-Host+ -NoTrace $message    

        $commandExpression = $Command
        $commandParametersKeys = (Get-Command $Command.Split(" ")[0]).parameters.keys
        
        # if (![string]::IsNullOrEmpty($ComputerName) -and $commandParametersKeys -contains "ComputerName") {$commandExpression += " -ComputerName $ComputerName"}
        # if (![string]::IsNullOrEmpty($Context) -and $commandParametersKeys -contains "Context") {$commandExpression += " -Context '$Context'"}
        if (![string]::IsNullOrEmpty($Reason) -and $commandParametersKeys -contains "Reason") {$commandExpression += " -Reason '$Reason'"}
        if (![string]::IsNullOrEmpty($RunId) -and $commandParametersKeys -contains "RunId") {$commandExpression += " -RunId '$RunId'"}
        
        Write-Host+ -NoTrace "Command: $commandExpression" 
        Write-Host+
        
        $result = Invoke-Expression -Command $commandExpression

        if ($azureUpdateMgmtFlags.HasFlag([AzureUpdateMgmtFlags]::ReenableMessaging)) {
            Enable-Messaging         
        }
        if ($azureUpdateMgmtFlags.HasFlag([AzureUpdateMgmtFlags]::ReenableMessagingWithDelay)) {
            Disable-Messaging -Duration $global:PlatformMessageDisabledTimeout -Reset   
        }

        $action = "Execute"; $status = "Completed"; $message = "$action $($Command): $status" 
        Write-Log -Action $action -Target $Command -Status $status -Message $message
        Write-Host+ -NoTrace $message 

        Send-AzureUpdateMgmtMessage -Command $Command -Reason $Reason -Status Completed   

    }

    Remove-PSSession+

    return $result

}