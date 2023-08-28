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

.PARAMETER OverwatchContext
    String used by Overwatch to determine the context of the command.
    Optional. The default value is "Azure Update Management"

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
    [Parameter(Mandatory=$false)][string]$OverwatchCommand,
    [Parameter(Mandatory=$false)][string]$OverwatchContext = "Azure Update Management",
    [Parameter(Mandatory=$false)][string]$OverwatchReason,
	[Parameter(Mandatory=$false)][string]$OverwatchController
)

$OverwatchRoot = "F:\Overwatch"
$OverwatchCommandScript = "azureupdatemgmt.ps1"
$OverwatchControllers = @("tbl-prod-01","tbl-test-01","ayx-control-01","tbl-mgmt-01")

Import-Module ThreadJob

#region Authentication

    # $ServicePrincipalConnection = Get-AutomationConnection -Name 'AzureRunAsConnection'

    # Connect-AzAccount `
    #     -ServicePrincipal `
    #     -TenantId $ServicePrincipalConnection.TenantId `
    #     -ApplicationId $ServicePrincipalConnection.ApplicationId `
    #     -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint

    try
    {
        "Logging in to Azure ..."
        Connect-AzAccount -Identity
        "Logging in to Azure ... SUCCESS"
    }
    catch {
        "Logging in to Azure ... FAILURE"
        Write-Error -Message $_.Exception
        throw $_.Exception
    }

#endregion Authentication

#region RunContext

    Write-Output ""
    
	Write-Output "OverwatchController: $OverwatchController"
	Write-Output "OverwatchCommand: $OverwatchCommand"
	Write-Output "OverwatchContext: $OverwatchContext"

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
				AzureVirtualMachines = switch ("$(($OverwatchController -split "-")[0])-$(($OverwatchController -split "-")[1])") {
					"tbl-test" {
						@(
							"/subscriptions/b102b6a8-f2ed-4096-83c7-a810539e7235/resourceGroups/apps-tableau-rg/providers/Microsoft.Compute/virtualMachines/tbl-test-02",
							"/subscriptions/b102b6a8-f2ed-4096-83c7-a810539e7235/resourceGroups/apps-tableau-rg/providers/Microsoft.Compute/virtualMachines/tbl-test-01"
						)
					}
					"tbl-prod" {
						@(
							"/subscriptions/b102b6a8-f2ed-4096-83c7-a810539e7235/resourceGroups/apps-tableau-rg/providers/Microsoft.Compute/virtualMachines/tbl-prod-02",
							"/subscriptions/b102b6a8-f2ed-4096-83c7-a810539e7235/resourceGroups/apps-tableau-rg/providers/Microsoft.Compute/virtualMachines/tbl-prod-01",
							"/subscriptions/b102b6a8-f2ed-4096-83c7-a810539e7235/resourceGroups/apps-tableau-rg/providers/Microsoft.Compute/virtualMachines/tbl-prod-03"
						)
					}
					"tbl-mgmt" {
						@(
							"/subscriptions/b102b6a8-f2ed-4096-83c7-a810539e7235/resourceGroups/apps-tableau-rg/providers/Microsoft.Compute/virtualMachines/tbl-mgmt-01"
						)
					}
					"ayx-control" {
						@(
							"/subscriptions/b102b6a8-f2ed-4096-83c7-a810539e7235/resourceGroups/apps-alteryx-rg/providers/Microsoft.Compute/virtualMachines/ayx-control-01",
							"/subscriptions/b102b6a8-f2ed-4096-83c7-a810539e7235/resourceGroups/apps-alteryx-rg/providers/Microsoft.Compute/virtualMachines/ayx-gallery-01",
							"/subscriptions/b102b6a8-f2ed-4096-83c7-a810539e7235/resourceGroups/apps-alteryx-rg/providers/Microsoft.Compute/virtualMachines/ayx-gallery-02",
							"/subscriptions/b102b6a8-f2ed-4096-83c7-a810539e7235/resourceGroups/apps-alteryx-rg/providers/Microsoft.Compute/virtualMachines/ayx-worker-01",
							"/subscriptions/b102b6a8-f2ed-4096-83c7-a810539e7235/resourceGroups/apps-alteryx-rg/providers/Microsoft.Compute/virtualMachines/ayx-worker-02",
							"/subscriptions/b102b6a8-f2ed-4096-83c7-a810539e7235/resourceGroups/apps-alteryx-rg/providers/Microsoft.Compute/virtualMachines/ayx-worker-03",
							"/subscriptions/b102b6a8-f2ed-4096-83c7-a810539e7235/resourceGroups/apps-alteryx-rg/providers/Microsoft.Compute/virtualMachines/ayx-worker-04"
						)
					}
				}
				Duration = "00:30:00"
				PSComputerName = "localhost" 
				PSShowComputerName = $true
				PSSourceJobInstanceId = $guid
			}
		}
	}

	$context = ConvertFrom-Json $SoftwareUpdateConfigurationRunContext
    $runId = $context.SoftwareUpdateConfigurationRunId
    $configName = $context.SoftwareUpdateConfigurationName

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
        $OverwatchReason = "Deployment schedule: $configName"
    }
	Write-Output "OverwatchReason: $OverwatchReason"

	# Write-Output ""
	# Write-Output "`$SoftwareUpdateConfigurationRunContext: $SoftwareUpdateConfigurationRunContext"
	# Write-Output ""

#endregion RunContext

#region ScriptBlock

    $scriptPath = "$runId.ps1"
    $scriptBlock = 
@"
Set-Location $OverwatchRoot
If (Test-Path -Path $OverwatchCommandScript) {
pwsh $OverwatchCommandScript -Command $OverwatchCommand -Context '$OverwatchContext' -Reason '$OverwatchReason' -RunId '$runId'
}
"@
    Out-File -FilePath $scriptPath -InputObject $scriptBlock

#endregion ScriptBlock

#region RunCommand

    $jobs = @()

    $vmIds | ForEach-Object {

        $vmId =  $_
        $split = $vmId -split "/";
        $resourceGroupName = $split[4];
        $vmName = $split[8];

		# Write-Output ""
		# Write-Output "VM"
		# Write-Output "--"
		# Write-Output "VmId: $vmId"
		# Write-Output "SubscriptionId: $subscriptionId"
		# Write-Output "ResourceGroupName: $resourceGroupName"
		# Write-Output "VmName: $vmName"
		# Write-Output "Overwatch Controller: $($OverwatchControllers -contains $vmName)"
		# Write-Output ""		

        if ($OverwatchControllers -contains $vmName) {
            Write-Output ""	
			Write-Output "Starting job on $vmName ... "
            $jobs += Start-ThreadJob -ScriptBlock {param($rg, $vm, $sp) Invoke-AzVMRunCommand -ResourceGroupName $rg -VmName $vm -CommandId 'RunPowerShellScript' -ScriptPath $sp -Parameter ${Source = "Azure"}} -ArgumentList $resourceGroupName, $vmName, $scriptPath
        }

    }

    if ($jobs) {

        $jobs = Wait-Job -Id $jobs.Id
        Write-Output "Job on $vmName has completed."
        Write-Output ""	

        foreach($job in $jobs) {

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

#endregion RunCommand

#region Cleanup

    Remove-Item -Path $scriptPath

#endregion Cleanup
