<#
.SYNOPSIS
    Executes an Overwatch command on an Azure VM.

.DESCRIPTION
    Executes an Overwatch command on an Azure VM.
    This script is intended to be run as a part of Update Management Pre/Post scripts. 

.PARAMETER SoftwareUpdateConfigurationRunContext
    A system variable which is automatically passed in by Update Management during a deployment.
    Optional. Supplied by Update Management.

.PARAMETER OverwatchCommand
    The Overwatch command to be executed.

.PARAMETER OverwatchReason
    The reason/purpose for executing the Overwatch command.
    Optional. The default value is an empty string.

.PARAMETER OverwatchController
    Specifies the target Overwatch controller when in INTERACTIVE mode.
    Optional. The default value is an empty string.

#>
#requires -Modules ThreadJob

param(
    [string]$SoftwareUpdateConfigurationRunContext,
    [Parameter(Mandatory=$true)][string]$OverwatchCommand,
    [Parameter(Mandatory=$false)][string]$OverwatchReason,
	[Parameter(Mandatory=$false)][string]$OverwatchController
)

$OverwatchRoot = "F:\Overwatch"
$OverwatchCommandScript = "azureupdatemgmt.ps1"
$OverwatchControllers = "<overwatchControllers>"

if ($OverwatchController -notin $OverwatchControllers) {
	throw "$OverwatchController is not a Overwatch controller"
}

Import-Module ThreadJob

#region AUTHENTICATION

    try
    {
        "Logging in to Azure ... "
        Connect-AzAccount -Identity
        "Logging in to Azure ... SUCCESS"
    }
    catch {
        "Logging in to Azure ... FAILURE"
        Write-Error -Message $_.Exception
        throw $_.Exception
    }

#endregion AUTHENTICATION
#region RUNCONTEXT

    Write-Output ""
    
	Write-Output "OverwatchController: $OverwatchController"
	Write-Output "OverwatchCommand:    $OverwatchCommand"

	#region DEBUG

		if (!$SoftwareUpdateConfigurationRunContext) {
			
			if (!$OverwatchController) {
				throw "`$OverwatchController must be specified when `$SoftwareUpdateConfigurationRunContext is null"
			}
			
			if ($OverwatchController -and $OverwatchControllers -notcontains $OverwatchController) {
				throw "$($OverwatchController) is not a valid Overwatch controller"
			}

			$guid = [guid]::NewGuid()
			
			$SoftwareUpdateConfigurationRunContext = ConvertTo-Json -Compress @{
				SoftwareUpdateConfigurationName = "Debug-$($OverwatchController)"
				SoftwareUpdateConfigurationRunId = $guid
				SoftwareUpdateConfigurationSettings = @{
					OperatingSystem = 1
					WindowsConfiguration = @{
						UpdateCategories = 32
						ExcludedKBNumbers = ""
						IncludedKBNumbers = ""
						RebootSetting = "Never"
					}
					LinuxConfiguration = $null
					Targets = @{
						azureQueries = $null
						nonAzureQueries = $null
					}
					NonAzureComputerNames = @()
					AzureVirtualMachines = "<azureVirtualMachines>"
					Duration = "00:30:00"
					PSComputerName = "localhost" 
					PSShowComputerName = $true
					PSSourceJobInstanceId = $guid
				}
			}
		}

	#endregion DEBUG

	$context = ConvertFrom-Json $SoftwareUpdateConfigurationRunContext
    $runId = $context.SoftwareUpdateConfigurationRunId

    $vmIds = $context.SoftwareUpdateConfigurationSettings.AzureVirtualMachines
    if (!$vmIds) 
    {
        $Settings = ConvertFrom-Json $context.SoftwareUpdateConfigurationSettings
        $vmIds = $Settings.AzureVirtualMachines
        if (!$vmIds) 
        {
            Write-Output "No Azure VMs found"
            return
        }
    }

	if (!$OverwatchReason) {
        $OverwatchReason = "None"
    }
	Write-Output "OverwatchReason: $OverwatchReason"

#endregion RUNCONTEXT
#region SCRIPTBLOCK

    $scriptPath = "$runId.ps1"
    $scriptBlock = 
@"
Set-Location $OverwatchRoot
If (Test-Path -Path $OverwatchCommandScript) {
pwsh $OverwatchCommandScript -Command $OverwatchCommand -Reason '$OverwatchReason' -RunId '$runId'
}
"@
    Out-File -FilePath $scriptPath -InputObject $scriptBlock

#endregion SCRIPTBLOCK
#region RUNCOMMAND

    $jobs = @()

    $vmIds | ForEach-Object {

        $vmId =  $_
        $split = $vmId -split "/";
        $resourceGroupName = $split[4];
        $vmName = $split[8];	

        if ($OverwatchController -eq $vmName) {
            Write-Output ""	
			Write-Output "Starting job on $OverwatchController ... "
            $jobs += Start-ThreadJob -ScriptBlock {param($rg, $vm, $sp) Invoke-AzVMRunCommand -ResourceGroupName $rg -VmName $vm -CommandId 'RunPowerShellScript' -ScriptPath $sp -Parameter ${Source = "Azure"}} -ArgumentList $resourceGroupName, $vmName, $scriptPath
        }

    }

    if ($jobs) {

		foreach ($job in $jobs) {
			Write-Output "Job $($job.Id) on $OverwatchController has started"
		}

        $jobs = Wait-Job -Id $jobs.Id

        foreach($job in $jobs) {

			Write-Output "Job $($job.Id) on $OverwatchController has completed"
			Write-Output ""	

            $job = Get-Job -Id $job.Id
            if ($job.Error) {
                Write-Output "Error"
                Write-Output "----------"                
                Write-Output "$($job.Error)"
            }
            else {
                $result = Receive-Job -Id $job.Id
                Write-Output "Result"
                Write-Output "----------"
                Write-Output "$($result.Value.Message)"
            }
        }

    }
    else {

        Write-Output "Error creating job[s]"
		
    }

#endregion RUNCOMMAND
#region CLEANUP

    Remove-Item -Path $scriptPath

#endregion CLEANUP