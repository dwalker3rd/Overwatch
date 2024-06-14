$ayxNode = "<ayxNode>"
$boxSync = "\\$ayxNode\boxsync"
$platformInstance = "<platformInstance>"
$csvPath = "\\$($boxSync)\<csvPath>\<csvFilename>"

$ayxWorkflows = import-csv $csvPath
foreach ($ayxWorkflow in $ayxWorkflows) {$ayxWorkflow.fullPath = "$($ayxWorkflow.directory -replace "<Box>", $boxSync)$($ayxWorkflow.workflow)"}
$ayxWorkflows | ConvertTo-Json | Out-File "F:\Overwatch\data\$($platformInstance)\workflows.json"

# copy from Box on an Alteryx Designer VM to Overwatch export directory
$ayxWorkflows | Foreach-Object {
    $destination = "F:\Overwatch\data\$($platformInstance)\.export\$($_.collectionIdUpdate)"
    if (!(Test-Path $destination)) { New-Item -ItemType Directory -Path $destination | Out-Null }
    copy-files $_.fullPath $destination -Overwrite
}

# get creds for this Azure storage container
$creds = get-credentials "<azure-storagecontainer-blob-admin>"

# delete files from Azure storage blob
azcopy rm "$($creds.UserName)/$($platformInstance)/?$($creds.GetNetworkCredential().Password)" --recursive=true

# copy to Azure storage blob
azcopy copy "F:\Overwatch\data\$($platformInstance)\.export\" "$($creds.UserName)/$($platformInstance)/?$($creds.GetNetworkCredential().Password)" --recursive=true

# delete files from Overwatch export directory
Remove-Item "F:\Overwatch\data\$($platformInstance)\.export\*" -Recurse -Force -ErrorAction SilentlyContinue