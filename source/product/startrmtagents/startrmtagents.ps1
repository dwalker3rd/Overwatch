#Requires -RunAsAdministrator
#Requires -Version 7

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"
$global:WriteHostPlusPreference = "Continue"

# product id must be set before definitions
$global:Product = @{Id="StartRMTAgents"}
. $PSScriptRoot\definitions.ps1

$sleepSeconds = 90
$sleepSecondsIncrement = 15
$sleepSecondsMax = 900

Write-Log -Context StartRMTAgents -Status Pending -Message "Starting $($global:Location.Scripts)\$($MyInvocation.MyCommand)" -Force

$rmtStatus = Get-RMTStatus -ResetCache

$agents = $rmtStatus.AgentStatus.Agent | Where-Object {!$_.Services.IsOK}
if ($agents) {

    $params = @{ 
        ComputerName = $agents.Name
        IfTableauServerIsRunning = $true
        Context = "StartRMTAgents"
    }
    $result = Start-RMTAgents @params

    $messageStatus = Send-PlatformStatusMessage -MessageType $global:PlatformMessageType.Alert
    $messageStatus | Out-Null

    $skippedEnvironments = $result.Skipped.Environments
    Write-Log -Context StartRMTAgents -Target Environments -Status Skipped -Message ("Skipped $($skippedEnvironments.Identifier -join ",")" ?? "None") -Force

    while ($skippedEnvironments.Count -gt 0) { 

        $message = "<Wait $sleepSeconds seconds <.>48> PENDING"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkYellow,DarkGray,DarkGray
        Write-Log -Context StartRMTAgents -Action Sleeping -Status Pending -Message "Wait $sleepSeconds seconds" -Force
        
        Start-Sleep -Seconds $sleepSeconds
        $sleepSeconds = $sleepSeconds -lt $sleepSecondsMax ? $sleepSeconds + $sleepSecondsIncrement : $sleepSecondsMax

        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen

        foreach ($environ in $skippedEnvironments) {

            Write-Host+

            $tableauServerStatus = Get-RMTTableauServerStatus -Environment $environ
            Write-Log -Context StartRMTAgents -Action Get-TableauServerStatus -Target $initialNode -Status $tsStatus.RollupStatus -Force

            Write-Host+

            if ($tableauServerStatus.IsOK) {
                $params = @{ 
                    EnvironmentIdentifier = $environ.Identifier
                    IfTableauServerIsRunning = $true
                    Context = "StartRMTAgents"
                }
                $result = Start-RMTAgents @params

                $messageStatus = Send-PlatformStatusMessage -MessageType $global:PlatformMessageType.Alert
                $messageStatus | Out-Null

                if ($result.Skipped.Agents.Count -eq 0) {
                    $skippedEnvironments = $skippedEnvironments | Where-Object {$_.Identifier -ne $environ.Identifier}
                    Write-Log -Context StartRMTAgents -Target Environments -Status Skipped -Message ("Skipped $($skippedEnvironments.Identifier -join ",")" ?? "None") -Force
                }
                else {
                    Write-Log -Context StartRMTAgents -Target Environments -Status Skipped -Message ("Skipped $($result.Skipped.Agents.Name -join ",")" ?? "None") -Force
                }

            }

        }

    }

}

Write-Host+
$message = "<All agents/environments <.>48> CONNECTED"
Write-Host+ -Iff (!$Quiet) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen    
Write-Host+

Write-Log -Context StartRMTAgents -Status Success -Message "All agents/environments are connected" -Force

Remove-PSSession+