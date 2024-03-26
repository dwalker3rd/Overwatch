$Prefix = "pathai"
$ProjectName = "dswin"
$ResourceGroupName = "aiprojects-dswin-rg"
$ResourceLocation = "uksouth"

$deployedResources = Get-AzDeployedResources -ProjectName $ProjectName

function Deploy-AzProjectDependencies {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ResourceType,
        [Parameter(Mandatory=$true)][string]$ResourceName,
        [Parameter(Mandatory=$false)][string]$DependentResourceType,
        [Parameter(Mandatory=$false)][string]$DependentResourceName,
        [Parameter(Mandatory=$false)][int]$RecursionLevel = 0
    )

    $dependencyObject = [ordered]@{
        Pass = $true
        Dependencies = @{}
    }

    foreach ($dependency in $global:Azure.ResourceTypes.$ResourceType.Dependencies.GetEnumerator()) {
        $dependencyResourceType = $dependency.Key
        $dependencyResourceName = $global:Azure.ResourceTypes.$dependencyResourceType.Name.Pattern
        foreach ($key in $dependency.Value.Keys) {
            $value = $dependency.Value.$($key)
            $dependencyResourceName = $dependencyResourceName -replace "<$key>", $value
        }
        $dependencyResourceName = Invoke-Expression $dependencyResourceName
        $dependencyResourceObject = ($deployedResources | Where-Object {$_.resourceType -eq $dependencyResourceType -and $_.resourceName -eq $dependencyResourceName}).resourceObject
        $_pass = $true
        if (!$dependencyResourceObject) {
            $_dependencyObject = Deploy-AzProjectDependencies -ResourceType $dependencyResourceType -ResourceName $dependencyResourceName -DependentResourceType $ResourceType -DependentResourceName $ResourceName -RecursionLevel ($RecursionLevel+1)
            if (!$_dependencyObject.Pass) { 
                Write-Host+ -NoTrace -NoTimestamp "throw error about which dependencies failed" -ForegroundColor Red
                $_pass = $false
            }
            $dependencyResourceObject = Deploy-AzProjectResource -ResourceType $dependencyResourceType -ResourceName $dependencyResourceName -dependency $_dependencyObject.Dependencies
            if (!$dependencyResourceObject) {
                $_pass = $_pass = $false
            }
            $deployedResources = Get-AzDeployedResources -ProjectName $ProjectName
        }
        $dependencyObject.Pass = $dependencyObject.Pass -and $_pass
        $dependencyObject.Dependencies += @{ 
            $($dependencyResourceType) = @{
                Pass = $_pass
                resourceObject = $dependencyResourceObject
                dependencyObject = $_dependencyObject
            }
        }
    }

    if ($RecursionLevel -eq 0) {
        if ($dependencyObject.Pass) {
            $resourceObject = ($deployedResources | Where-Object {$_.resourceType -eq $ResourceType -and $_.resourceName -eq $ResourceName}).resourceObject
            if (!$resourceObject) {
                $resourceObject = Deploy-AzProjectResource -ResourceType $ResourceType -ResourceName $ResourceName -dependency $dependencyObject.Dependencies
            }
            $dependencyObject.Pass = $dependencyObject.Pass -and $null -ne $resourceObject
        }
        $dependencyObject += @{ 
            $($resourceType) = $resourceObject
        }
    }

    return $dependencyObject

}

function Deploy-AzProjectResource {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ResourceType,
        [Parameter(Mandatory=$true)][string]$ResourceName,
        [Parameter(Mandatory=$false)][object]$Dependencies
    )

    $object = $null
    try {
        switch ($resourceType) {
            "ApplicationInsights" {
                $object = New-AzApplicationInsights -ResourceGroupName $resourceGroupName -Name $resourceName -Location $resourceLocation -WorkspaceResourceId $Dependencies.OperationalInsightsWorkspace.resourceObject.ResourceId
                break
            }
            "OperationalInsightsWorkspace" {
                $object = New-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $resourceName -Location $resourceLocation
                $_operationalInsightsWorkspaceLinkedStorageAccount = New-AzOperationalInsightsLinkedStorageAccount -ResourceGroupName $resourceGroupName -WorkspaceName $resourceName -DataSourceType "CustomLogs" -StorageAccountId $Dependencies.StorageAccount.resourceObject.Id
                $_operationalInsightsWorkspaceLinkedStorageAccount | Out-Null
                # if (!$_operationalInsightsWorkspaceLinkedStorageAccount) throw message, log, something
                break
            }
            "StorageAccount" {
                $storageAccountParameters = Get-AzProjectStorageAccountParameters
                $params = @{
                    Name = $resourceName
                    ResourceGroupName = $resourceGroupName
                    Location = $resourceLocation
                    SKU = $storageAccountParameters.StorageAccountSku
                    Kind = $storageAccountParameters.StorageAccountKind
                }
                $object = New-AzStorageAccount+ @params
                $resource.resourceContext = New-AzStorageContext -StorageAccountName $resourceName -UseConnectedAccount -ErrorAction SilentlyContinue
                break
            }
            "StorageContainer" {
                $object = New-AzStorageContainer+ -Context $Dependencies.StorageAccount.resourceObject.Context -Name $resourceName
                break
            }
            "MLWorkspace" {
                $_mlWorkspaceParams = @{
                    Name = $resourceName
                    ResourceGroupName = $resourceGroupName
                    Location = $resourceLocation
                    ApplicationInsightID = $Dependencies.ApplicationInsights.resourceObject.Id
                    KeyVaultId = $Dependencies.KeyVault.resourceObject.ResourceId
                    StorageAccountId = $Dependencies.StorageAccount.resourceObject.Id
                    IdentityType = 'SystemAssigned'
                }
                $object = New-AzMLWorkspace @_mlWorkspaceParams
                break
            }
        }
    }
    catch {
        Write-Host+ -NoTrace $_.Exception.Message -ForegroundColor DarkRed
    }

    return $object

}