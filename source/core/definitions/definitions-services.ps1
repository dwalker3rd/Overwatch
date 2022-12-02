#region SERVICES

# Order of service definitions is critical!
# Services do not currently specify dependencies

. "$($global:Location.Services)\vault.ps1"
. "$($global:Location.Services)\encryption.ps1"
. "$($global:Location.Services)\credentials.ps1"

if (Test-Path -Path "$($global:Location.Services)\services-os-stubs.ps1") {. "$($global:Location.Services)\services-os-stubs.ps1"}
if (Test-Path -Path "$($global:Location.Services)\services-$($global:Environ.OS).ps1") {. "$($global:Location.Services)\services-$($global:Environ.OS).ps1"}

if (Test-Path -Path "$($global:Location.Services)\services-platform-stubs.ps1") {. "$($global:Location.Services)\services-platform-stubs.ps1"}
if (Test-Path -Path "$($global:Location.Services)\services-$($global:Environ.Platform)*.ps1") {
    Get-Item "$($global:Location.Services)\services-$($global:Environ.Platform)*.ps1" | Sort-Object -Property Name | Foreach-Object {. "$($global:Location.Services)\$($_.Name)"}
}

if (Test-Path -Path "$($global:Location.Services)\services-$($global:Overwatch.Name).ps1") {. "$($global:Location.Services)\services-$($global:Overwatch.Name).ps1"}

. "$($global:Location.Services)\heartbeat.ps1"
. "$($global:Location.Services)\files.ps1"
. "$($global:Location.Services)\logging.ps1"
. "$($global:Location.Services)\cache.ps1"
. "$($global:Location.Services)\tasks.ps1"
. "$($global:Location.Services)\events.ps1"
. "$($global:Location.Services)\topology.ps1"
. "$($global:Location.Services)\messaging.ps1"
. "$($global:Location.Services)\contacts.ps1"
. "$($global:Location.Services)\python.ps1"
. "$($global:Location.Services)\connectionstrings.ps1"
. "$($global:Location.Services)\odbc.ps1"

if (Test-Path -Path "$($global:Location.Services)\services-$($global:Product.Id).ps1") {. "$($global:Location.Services)\services-$($global:Product.Id).ps1"}
if (Test-Path -Path "$($global:Location.Services)\services-$($global:Provider.Id).ps1") {. "$($global:Location.Services)\services-$($global:Provider.Id).ps1"}

