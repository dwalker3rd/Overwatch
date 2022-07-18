#region SERVICES

# Order of service definitions is critical!
# Services do not currently specify dependencies

$servicesPath = $global:Location.Services

. $servicesPath\vault.ps1
. $servicesPath\encryption.ps1
. $servicesPath\credentials.ps1

if (Test-Path -Path $servicesPath\services-os-stubs.ps1) {. $servicesPath\services-os-stubs.ps1}
if (Test-Path -Path $servicesPath\services-$($global:Environ.OS).ps1) {. $servicesPath\services-$($global:Environ.OS).ps1}

if (Test-Path -Path $servicesPath\services-platform-stubs.ps1) {. $servicesPath\services-platform-stubs.ps1}
if (Test-Path -Path $servicesPath\services-$($global:Environ.Platform)*.ps1) {
    Get-Item $servicesPath\services-$($global:Environ.Platform)*.ps1 | Sort-Object -Property Name | Foreach-Object {. "$servicesPath\$($_.Name)"}
}

if (Test-Path -Path $servicesPath\services-$($global:Overwatch.Name).ps1) {. $servicesPath\services-$($global:Overwatch.Name).ps1}

. $servicesPath\heartbeat.ps1
. $servicesPath\files.ps1
. $servicesPath\logging.ps1
. $servicesPath\cache.ps1
. $servicesPath\tasks.ps1
. $servicesPath\events.ps1
. $servicesPath\messaging.ps1
. $servicesPath\contacts.ps1
. $servicesPath\python.ps1
. $servicesPath\connectionstrings.ps1
. $servicesPath\odbc.ps1

if (Test-Path -Path $servicesPath\services-$($global:Product.Id).ps1) {. $servicesPath\services-$($global:Product.Id).ps1}
if (Test-Path -Path $servicesPath\services-$($global:Provider.Id).ps1) {. $servicesPath\services-$($global:Provider.Id).ps1}

