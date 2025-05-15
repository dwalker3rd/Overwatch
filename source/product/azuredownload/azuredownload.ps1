# #Requires -RunAsAdministrator
# #Requires -Version 7

# $global:DebugPreference = "SilentlyContinue"
# $global:InformationPreference = "SilentlyContinue"
# $global:VerbosePreference = "SilentlyContinue"
# $global:WarningPreference = "Continue"
# $global:ProgressPreference = "SilentlyContinue"
# $global:PreflightPreference = "SilentlyContinue"
# $global:PostflightPreference = "SilentlyContinue"
# $global:WriteHostPlusPreference = "Continue"

# $global:Product = @{Id = "AzureDownload"}
# . $PSScriptRoot\definitions.ps1

Write-Host+
$message = "<Downloading files from Azure Storage <.>48> PENDING"
Write-Host+ -NoTimestamp -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray 

$downloads = Import-Csv -Path "$($global:Location.Data)\azureDownload.csv"
foreach ($download in $downloads) { 

    $resourceGroup = $download.resourceGroup
    $storageAccountName = $download.storageAccountName
    $containerName = $download.containerName
    $storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroup -Name $storageAccountName)[0].Value
    $storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey 
    $blobFilePath = $download.blobFilePath
    $localFilePath = "$($global:Location.Data)\$($download.localFilePath)"

    Get-AzStorageBlobContent -Container $containerName -Blob $blobFilePath -Destination $localFilePath -Context $storageContext -Force    

}

Write-Host+
$message = "<Downloaded files from Azure Storage <.>48> SUCCESS"
Write-Host+ -NoTimestamp -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
Write-Host+
