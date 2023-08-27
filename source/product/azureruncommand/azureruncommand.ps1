#Requires -RunAsAdministrator
#Requires -Version 7

[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

param(
    [Parameter(Mandatory=$false,Position=0)][string]$Command,
    [Parameter(Mandatory=$false)][string]$OverwatchController = $env:COMPUTERNAME,
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
    Write-Host+ "[$($MyInvocation.MyCommand)] PENDING "
    # enter any command here for testing Overwatch's AzureRunCommand with Azure Automation 
    Write-Host+ "[$($MyInvocation.MyCommand)] FINISHED"
}
function Test-MessagingOnStop { 
    Write-Host+ "[$($MyInvocation.MyCommand)] PENDING "
    $global:PlatformMessageType.Values | Where-Object {$_ -notin ("UserNotification","Heartbeat")} | ForEach-Object {
        Send-TaskMessage -Id Monitor -Status Testing -MessageType $_ -Message "Testing $($_.ToLower()) message via AzureRunCommand\$($MyInvocation.MyCommand)" | Out-Null
    }
    Write-Host+ "[$($MyInvocation.MyCommand)] FINISHED"
}
function Test-MessagingOnStart { 
    Write-Host+ "[$($MyInvocation.MyCommand)] PENDING "
    $global:PlatformMessageType.Values | Where-Object {$_ -notin ("UserNotification","Heartbeat")} | ForEach-Object {
        Send-TaskMessage -Id Monitor -Status Testing -MessageType $_ -Message "Testing $($_.ToLower()) message via AzureRunCommand\$($MyInvocation.MyCommand)" | Out-Null
    }
    Write-Host+ "[$($MyInvocation.MyCommand)] FINISHED"
}
function Test-MessagingOnIntervention { 
    Write-Host+ "[$($MyInvocation.MyCommand)] PENDING "

    $_platformStatus = Get-PlatformStatus -CacheOnly
    $_platformStatus.Intervention = $true 
    $_platformStatus | Write-Cache platformstatus

    Send-TaskMessage -Id Monitor -Status Testing -MessageType $global:PlatformMessageType.Information -Message "Testing information message via AzureRunCommand\$($MyInvocation.MyCommand)" | Out-Null
    
    Write-Host+ "[$($MyInvocation.MyCommand)] FINISHED"
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

        $action = "Remoting to $OverwatchController using CredSSP"; $status = "Start"; $message = "$($action): $status" 
        Write-Log -Context $Context -Action $action -Target $Command -Status $status -Message $message
        Write-Host+ -NoTrace $message   

        # disable messaging when azure remote command is stop-platform
        # assumption: azure remote command start-platform will follow stop-platform
        # messaging will be enabled at end azure remote command start-platform
        # note: intervention message types are always sent and will re-enable messaging
        if ($Command.ToLower() -in ("stop-platform","test-messagingonstop")) {
            Disable-Messaging -Duration (New-Timespan -Minutes 90) -Notify  
        }

        $creds = Get-Credentials "localadmin-$($Platform.Instance)" -LocalMachine

        $workingDirectory = $global:Location.Root
        $result = Invoke-Command -ComputerName $OverwatchController `
            -ScriptBlock {
                    Set-Location $using:workingDirectory; 
                    pwsh azureruncommand.ps1 -Command $using:Command -Context $using:Context -Reason $using:Reason -NoDoubleHop -CredSSP -SkipPreflight
                } `
            -Authentication Credssp `
            -Credential $creds 

        $action = "Remoting to $OverwatchController using CredSSP"; $status = "Completed"; $message = "$($action): $status" 
        Write-Log -Context $Context -Action $action -Target $Command -Status $status -Message $message
        Write-Host+ -NoTrace $message         

    }
    else {

        $global:WriteHostPlusPreference = "SilentlyContinue"

        # product id must be set before include files
        $global:Product = @{Id="AzureRunCommand"}
        . $PSScriptRoot\definitions.ps1

        $global:WriteHostPlusPreference = "Continue"

        $action = "Execute"; $status = "Start"; $message = "$action $($Command): $status" 
        Write-Log -Context $Context -Action $action -Target $Command -Status $status -Message $message
        Write-Host+ -NoTrace $message    

        $commandExpression = $Command
        $commandParametersKeys = (Get-Command $Command.Split(" ")[0]).parameters.keys
        
        # if (![string]::IsNullOrEmpty($ComputerName) -and $commandParametersKeys -contains "ComputerName") {$commandExpression += " -ComputerName $ComputerName"}
        if (![string]::IsNullOrEmpty($Context) -and $commandParametersKeys -contains "Context") {$commandExpression += " -Context '$Context'"}
        if (![string]::IsNullOrEmpty($Reason) -and $commandParametersKeys -contains "Reason") {$commandExpression += " -Reason '$Reason'"}
        if (![string]::IsNullOrEmpty($RunId) -and $commandParametersKeys -contains "RunId") {$commandExpression += " -RunId '$RunId'"}
        
        Write-Host+ -NoTrace "Command: $commandExpression" 
        Write-Host+
        
        $result = Invoke-Expression -Command $commandExpression

        $action = "Execute"; $status = "Completed"; $message = "$action $($Command): $status" 
        Write-Log -Context $Context -Action $action -Target $Command -Status $status -Message $message
        Write-Host+ -NoTrace $message 

        # enable messaging if needed
        # note: see disable messaaging above
        if ($Command.ToLower() -in ("start-platform","test-messagingonstart")) {
            Enable-Messaging -Notify            
        }

    }

    Remove-PSSession+

    return $result

}