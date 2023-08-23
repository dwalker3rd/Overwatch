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

function Test-AzureRunCommand { 

    Write-Host+ "[Test-AzureRunCommand] PENDING "

    # enter any command here for testing Overwatch's AzureRunCommand with Azure Automation 
    Send-TaskMessage -Id Monitor -Status Running -MessageType $PlatformMessageType.Intervention -Message "Intervention Test"

    Write-Host+ "[Test-AzureRunCommand] FINISHED"
    
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

$result = $null
if ($Command) {

    if (!$NoDoubleHop -and $Context -like "Azure*") {
        $DoubleHop = $true
        $global:UseCredssp = $true
    }

    if ($DoubleHop) {

        $SkipPreflight = $true

        # product id must be set before include files
        $global:Product = @{Id="AzureRunCommand"}
        . $PSScriptRoot\definitions.ps1

        # disable messaging for the specified duration and send message
        # note that messages of type intervention or from source "Send-MessageStatus" are not affected
        Disable-Messaging -Duration (New-Timespan -Minutes 90) -Notify  

        Write-Host+ -NoTrace "Remoting to $OverwatchController using CredSSP `"double hop`"." 

        $creds = Get-Credentials "localadmin-$($Platform.Instance)" -LocalMachine

        $workingDirectory = $global:Location.Root
        $result = Invoke-Command -ComputerName $OverwatchController `
            -ScriptBlock {
                    Set-Location $using:workingDirectory; 
                    pwsh azureruncommand.ps1 -Command $using:Command -Context $using:Context -Reason $using:Reason -NoDoubleHop -Credssp -SkipPreflight
                } `
            -Authentication Credssp `
            -Credential $creds 

    }
    else {

        $global:WriteHostPlusPreference = "SilentlyContinue"

        # product id must be set before include files
        $global:Product = @{Id="AzureRunCommand"}
        . $PSScriptRoot\definitions.ps1

        $global:WriteHostPlusPreference = "Continue"

        # disable messaging for the specified duration and send message
        # note that messages of type intervention or from source "Send-MessageStatus" are not affected
        Disable-Messaging -Duration (New-Timespan -Minutes 90) -Notify

        $commandExpression = $Command
        $commandParametersKeys = (Get-Command $Command.Split(" ")[0]).parameters.keys
        
        # if (![string]::IsNullOrEmpty($ComputerName) -and $commandParametersKeys -contains "ComputerName") {$commandExpression += " -ComputerName $ComputerName"}
        if (![string]::IsNullOrEmpty($Context) -and $commandParametersKeys -contains "Context") {$commandExpression += " -Context '$Context'"}
        if (![string]::IsNullOrEmpty($Reason) -and $commandParametersKeys -contains "Reason") {$commandExpression += " -Reason '$Reason'"}
        if (![string]::IsNullOrEmpty($RunId) -and $commandParametersKeys -contains "RunId") {$commandExpression += " -RunId '$RunId'"}
        
        Write-Host+ -NoTrace "Command: $commandExpression" 
        Write-Host+
        
        $result = Invoke-Expression -Command $commandExpression

        Enable-Messaging -Notify

    }

    Remove-PSSession+

    return $result

}