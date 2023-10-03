
<#PSScriptInfo

.VERSION 1.2

.GUID 9606f2a1-49f8-4a67-91d6-23fc6ebf5b3b

.AUTHOR zachal

.COMPANYNAME Microsoft 

.COPYRIGHT 

.TAGS UpdateManagement, Automation

.LICENSEURI 

.PROJECTURI 

.ICONURI 

.EXTERNALMODULEDEPENDENCIES ThreadJob

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES
Removed parameters AutomationAccount, ResourceGroup

.PRIVATEDATA 

#>

<# 

.DESCRIPTION 
  This script is intended to be run as a part of Update Management Pre/Post scripts. 
  It requires a System Managed Identity.
  This script will turn off all Azure VMs that were started by the Update Management Turn Off VMs runbook.
  It retrieves the list of VMs that were started from an Automation Account variable.
 

#> 

#requires -Modules ThreadJob
<#
.SYNOPSIS
 Stop VMs that were started as part of an Update Management deployment

.DESCRIPTION
  This script is intended to be run as a part of Update Management Pre/Post scripts. 
  It requires a System Managed Identity.
  This script will turn off all Azure VMs that were started by the Update Management Turn Off VMs runbook.
  It retrieves the list of VMs that were started from an Automation Account variable.

.PARAMETER SoftwareUpdateConfigurationRunContext
  This is a system variable which is automatically passed in by Update Management during a deployment.

#>

param(
    [string]$SoftwareUpdateConfigurationRunContext
)

#region BoilerplateAuthentication
#This requires a System Managed Identity
$AzureContext = (Connect-AzAccount -Identity).context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext
#endregion BoilerplateAuthentication

#If you wish to use the run context, it must be converted from JSON
$context = ConvertFrom-Json  $SoftwareUpdateConfigurationRunContext
# $runId = "PrescriptContext" + $context.SoftwareUpdateConfigurationRunId

#https://github.com/azureautomation/runbooks/blob/master/Utility/ARM/Find-WhoAmI
# In order to prevent asking for an Automation Account name and the resource group of that AA,
# search through all the automation accounts in the subscription 
# to find the one with a job which matches our job ID
$AutomationResource = Get-AzResource -ResourceType Microsoft.Automation/AutomationAccounts

foreach ($Automation in $AutomationResource)
{
    $Job = Get-AzAutomationJob -ResourceGroupName $Automation.ResourceGroupName -AutomationAccountName $Automation.Name -Id $PSPrivateMetadata.JobId.Guid -ErrorAction SilentlyContinue
    if (!([string]::IsNullOrEmpty($Job)))
    {
        $ResourceGroup = $Job.ResourceGroupName
        $AutomationAccount = $Job.AutomationAccountName
        break;
    }
}

#Retrieve the automation variable, which we named using the runID from our run context. 
#See: https://docs.microsoft.com/en-us/azure/automation/automation-variables#activities
$variable = Get-AzAutomationVariable -Name UpdateManagementTurnOnVMsCache -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount
if (!$variable) 
{
    Write-Output "No machines to turn off"
    return
}

$vmIds = $variable.Value -split ","
$stoppableStates = "starting", "running"
$jobIDs= New-Object System.Collections.Generic.List[System.Object]

#This script can run across subscriptions, so we need unique identifiers for each VMs
#Azure VMs are expressed by:
# subscription/$subscriptionID/resourcegroups/$resourceGroup/providers/microsoft.compute/virtualmachines/$name
$vmIds | ForEach-Object {
    $vmId =  $_
    
    $split = $vmId -split "/";
    $subscriptionId = $split[2]; 
    $rg = $split[4];
    $name = $split[8];
    Write-Output ("Subscription Id: " + $subscriptionId)
    $mute = Set-AzContext -Subscription $subscriptionId

    $vm = Get-AzVM -ResourceGroupName $rg -Name $name -Status -DefaultProfile $mute

    $state = ($vm.Statuses[1].DisplayStatus -split " ")[1]
    if($state -in $stoppableStates) {
        Write-Output "Stopping '$($name)' ..."
        $newJob = Start-ThreadJob -ScriptBlock { param($resource, $vmname, $sub) $context = Set-AzContext -Subscription $sub; Stop-AzVM -ResourceGroupName $resource -Name $vmname -Force -DefaultProfile $context} -ArgumentList $rg,$name,$subscriptionId
        $jobIDs.Add($newJob.Id)
    }else {
        Write-Output ($name + ": already stopped. State: " + $state) 
    }
}
#Wait for all machines to finish stopping so we can include the results as part of the Update Deployment
$jobsList = $jobIDs.ToArray()
if ($jobsList)
{
    Write-Output "Waiting for machines to finish stopping..."
    Wait-Job -Id $jobsList
}

foreach($id in $jobsList)
{
    $job = Get-Job -Id $id
    if ($job.Error)
    {
        Write-Output $job.Error
    }
}
#Clean up our variables:
Remove-AzAutomationVariable -AutomationAccountName $AutomationAccount -ResourceGroupName $ResourceGroup -name UpdateManagementTurnOnVMsCache
