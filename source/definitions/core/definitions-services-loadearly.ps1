#region SERVICES

# Order of service definitions is critical!
# Services do not currently specify dependencies

$servicesPath = $global:Location.Services

if (Test-Path -Path $servicesPath\services-$($global:Overwatch.Name)-loadearly.ps1) {. $servicesPath\services-$($global:Overwatch.Name)-loadearly.ps1}