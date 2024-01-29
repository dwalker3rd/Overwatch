function global:Find-TSObjectsWithGroupPermission {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string[]]$Name,
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers),
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+ -Users $Users -Groups $Groups),
        [Parameter(Mandatory=$false)][object]$Datasources = (Get-TSDatasources+ -Users $Users -Groups $Groups -Projects $Projects),
        [Parameter(Mandatory=$false)][object]$Workbooks = ( Get-TSWorkbooks+ -Users $Users -Groups $Groups -Projects $Projects)
    )

    $adGroups = foreach ($adGroupName in $Name) {
        Find-TSGroup -Name $adGroupName -Groups $Groups
    }

    $results = @()

    foreach ($tsProject in $Projects) {
        foreach ($adGroup in $adGroups) {
            if ($adGroup.id -in $tsProject.permissions.granteecapabilities.group.id) {
                $results += @{
                    type = "project"
                    name = $tsProject.name
                    permissions = ""
                    projectName = $tsProject.name
                    projectId = $tsProject.id
                    groupName = $adGroup.name
                    groupId = $adGroup.Id
                }
            }
        }
    }

    foreach ($tsDatasource in $Datasources) {
        foreach ($adGroup in $adGroups) {
            if ($adGroup.id -in $tsDatasource.permissions.granteecapabilities.group.id) {
                $results += @{
                    type = "datasource"
                    name = $tsDatasource.name
                    permissions = ($Projects | Where-Object {$_.id -eq $tsDatasource.project.id}).contentPermissions
                    projectName = $tsDatasource.project.name
                    projectId = $tsDatasource.project.id
                    groupName = $adGroup.name
                    groupId = $adGroup.Id
                }
            }
        }
    }

    foreach ($tsWorkbook in $Workbooks) {
        foreach ($adGroup in $adGroups) {
            if ($adGroup.id -in $tsWorkbook.permissions.granteecapabilities.group.id) {
                $results += @{
                    type = "workbook"
                    name = $tsWorkbook.name
                    permissions = ($Projects | Where-Object {$_.id -eq $tsWorkbook.project.id}).contentPermissions
                    projectName = $tsWorkbook.project.name
                    projectId = $tsWorkbook.project.id
                    groupName = $adGroup.name
                    groupId = $adGroup.Id
                }
            }
        }
    }

    return $results | ConvertTo-PSCustomObject

}

# 2024 CVIA Organizational Changes
$groupNames = @(
    "Dept-CEDD-CVIA Enteric & Diarrheal Diseases Area",
    "Dept-CMAL-CVIA Malaria Disease Area",
    "Dept-CPOL-CVIA Polio Disease Area",
    "Dept-CRIM-CVIA Respiratory Infections & Maternal Immunizations D",
    "Auto-EM and Internal Partners",
    "Auto-EM-Division-Essential Medicines"
)

Connect-TableauServer -Site PATHOperations

# $tsUsers = Get-TSUsers
# $tsGroups = Get-TSGroups
# $tsProjects = Get-TSProjects+ -Users $tsUsers -Groups $tsGroups
# $tsDatasources = Get-TSDatasources+ -Users $tsUsers -Groups $tsGroups -Projects $tsProjects
# $tsWorkbooks = Get-TSWorkbooks+ -Users $tsUsers -Groups $tsGroups -Projects $tsProjects

$results = Find-TSObjectsWithGroupPermission -Name $groupNames -Users $tsUsers -Groups $tsGroups -Projects $tsProjects -Datasources $tsDatasources -Workbooks $tsWorkbooks
$results | Select-Object -Property type,name,projectName,projectId,permissions,groupName | Format-Table
# $results | Select-Object -Property type,name,projectName,projectId,permissions,groupName | Export-Csv "$($global:Location.Data)\tsObjectsWithGroupPermission.csv" -Encoding utf8 -UseQuotes AsNeeded