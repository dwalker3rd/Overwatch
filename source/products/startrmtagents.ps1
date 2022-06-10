#Requires -RunAsAdministrator
#Requires -Version 7

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "Continue"
$global:PostflightPreference = "Continue"

# product id must be set before definitions
$global:Product = @{Id="StartRMTAGents"}
. $PSScriptRoot\definitions.ps1

$sleepSeconds = 90
$sleepSecondsIncrement = 15
$sleepSecondsMax = 900

Write-Log -Context StartRMTAgents -Status Pending -Message "Starting $($global:Location.Scripts)\$($MyInvocation.MyCommand)" -Force

$rmtStatus = Get-RMTStatus -ResetCache

$agents = $rmtStatus.AgentStatus.Agents | Where-Object {!$_.Services.IsOK}
if ($agents) {

    $params = @{ 
        Command = "Start"
        ComputerName = $agents.Name
        IfTableauServerIsRunning = $true
    }
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    $result = Request-RMTAgents @params

    $skippedEnvironments = $result.Skipped.Environments
    Write-Log -Context StartRMTAgents -Target Environments -Status Skipped -Data (($skippedEnvironments.Identifier | ConvertTo-Json -Compress) ?? "None") -Force

    while ($skippedEnvironments.Count -gt 0) { 

        $message = "Wait $sleepSeconds seconds : PENDING"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkYellow,DarkGray,DarkGray
        Write-Log -Context StartRMTAgents -Action Sleeping -Status Pending -Data "$sleepSeconds seconds" -Force
        
        Start-Sleep -Seconds $sleepSeconds
        $sleepSeconds = $sleepSeconds -lt $sleepSecondsMax ? $sleepSeconds + $sleepSecondsIncrement : $sleepSecondsMax

        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen

        foreach ($environ in $skippedEnvironments) {

            Write-Host+

            $tableauServerStatus = Get-RMTTableauServerStatus -Environment $environ
            Write-Log -Action Get-TableauServerStatus -Target $initialNode -Status $tsStatus.RollupStatus  -Force

            Write-Host+

            if ($tableauServerStatus.IsOK) {
                $params = @{ 
                    Command = "Start"
                    EnvironmentIdentifier = $environ.Identifier
                    IfTableauServerIsRunning = $true
                }
                if ($Context) { $params += @{ Context = $Context } }
                if ($Reason) { $params += @{ Reason = $Reason } }
                $result = Request-RMTAgents @params

                if ($result.Skipped.Agents.Count -eq 0) {
                    $skippedEnvironments = $skippedEnvironments | Where-Object {$_.Identifier -ne $environ.Identifier}
                    Write-Log -Context StartRMTAgents -Target Environments -Status Skipped -Data (($skippedEnvironments.Identifier | ConvertTo-Json -Compress) ?? "None") -Force
                }
            }

        }

    }

}

Write-Host+
$message = "All agents/environments : Connected"
Write-Host+ -Iff (!$Quiet) -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGreen    
Write-Host+

Write-Log -Context StartRMTAgents -Status Success -Message $message.Replace(":","are") -Force