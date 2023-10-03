param (
    [switch]$UseDefaultResponses
)

$_product = Get-Product "AzureProjects"
$_product | Out-Null

if (!(Test-Path -Path "$($global:Location.Data)\azure")) {
    New-Item -Path "$($global:Location.Data)" -Name "azure" -ItemType "directory" | Out-Null
}

# Azure Deployment Code/Data
Expand-Archive "$($global:Location.Root)\source\product\$($_product.id.tolower())\deployment.zip" "$($global:Location.Root)\data\azure" -Force