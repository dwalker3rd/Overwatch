$tableauCreators = Import-CSV -Path "$($global:Location.Data)\tableau\Tableau Creators.csv"
$tableauCreatorsNonPath = $tableauCreators | Where-Object {$_.domain -ne "path.org"}

$tableauCreatorsNonPath | Add-Member -NotePropertyName site_name -NotePropertyValue "" -Force
foreach ($tableauCreatorNonPath in $tableauCreatorsNonPath) {
    $tableauCreatorNonPath.site_name = ($tsServerUsers | Where-Object {$_.name -eq $tableauCreatorNonPath.email}).site.name -join ", "
}
$tableauCreatorsNonPathWithSite = $tableauCreatorsNonPath | Where-Object {$_.site_name}
$tableauCreatorsNonPathWithSite | Select-Object -Property product_name,product_version,last_installed,period_end,expired,user_name,email,domain,site_name | Sort-Object -Property last_installed -Descending | Format-Table

$tableauCreatorsNonPathNoSite = $tableauCreatorsNonPath | Where-Object {!$_.site_name}
$tableauCreatorsNonPathNoSite | Select-Object -Property product_name,product_version,last_installed,period_end,expired,user_name,email,domain | Sort-Object -Property last_installed -Descending | Format-Table