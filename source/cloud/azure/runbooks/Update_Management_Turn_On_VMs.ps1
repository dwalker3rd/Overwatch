
<#PSScriptInfo

.VERSION 1.4

.GUID 5fbe9d16-981d-4a88-874c-365d46c1fcc2

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
  A System Managed Identity is required.
  This script will ensure all Azure VMs in the Update Deployment are running so they recieve updates.
  This script will store the names of machines that were started in an Automation variable so that those machines
  can be turned back off by the Update Management Turn Off VMs runbook
 

#> 

#requires -Modules ThreadJob
<#
.SYNOPSIS
 Start VMs as part of an Update Management deployment

.DESCRIPTION
  This script is intended to be run as a part of Update Management Pre/Post scripts. 
  A System Managed Identity is required.
  This script will ensure all Azure VMs in the Update Deployment are running so they recieve updates.
  This script will store the names of machines that were started in an Automation variable so that those machines
  can be turned back off by the Update Management Turn Off VMs runbook

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
$vmIds = $context.SoftwareUpdateConfigurationSettings.AzureVirtualMachines
# $runId = "PrescriptContext" + $context.SoftwareUpdateConfigurationRunId

if (!$vmIds) 
{
    #Workaround: Had to change JSON formatting
    $Settings = ConvertFrom-Json $context.SoftwareUpdateConfigurationSettings
    #Write-Output "List of settings: $Settings"
    $VmIds = $Settings.AzureVirtualMachines
    #Write-Output "Azure VMs: $VmIds"
    if (!$vmIds) 
    {
        Write-Output "No Azure VMs found"
        return
    }
}

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

#This is used to store the state of VMs
New-AzAutomationVariable -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount -Name UpdateManagementTurnOnVMsCache -Value "" -Encrypted $false

$updatedMachines = @()
$startableStates = "stopped" , "stopping", "deallocated", "deallocating"
$jobIDs= New-Object System.Collections.Generic.List[System.Object]

#Parse the list of VMs and start those which are stopped
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

    #Query the state of the VM to see if it's already running or if it's already started
    $state = ($vm.Statuses[1].DisplayStatus -split " ")[1]
    if($state -in $startableStates) {
        Write-Output "Starting '$($name)' ..."
        #Store the VM we started so we remember to shut it down later
        $updatedMachines += $vmId
        $newJob = Start-ThreadJob -ScriptBlock { param($resource, $vmname, $sub) $context = Set-AzContext -Subscription $sub; Start-AzVM -ResourceGroupName $resource -Name $vmname -DefaultProfile $context} -ArgumentList $rg,$name,$subscriptionId
        $jobIDs.Add($newJob.Id)
    }else {
        Write-Output ($name + ": no action taken. State: " + $state) 
    }
}

$updatedMachinesCommaSeparated = $updatedMachines -join ","
#Wait until all machines have finished starting before proceeding to the Update Deployment
$jobsList = $jobIDs.ToArray()
if ($jobsList)
{
    Write-Output "Waiting for machines to finish starting..."
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

Write-output $updatedMachinesCommaSeparated
#Store output in the automation variable
Set-AzAutomationVariable -Name UpdateManagementTurnOnVMsCache -Value $updatedMachinesCommaSeparated -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount -Encrypted $false
