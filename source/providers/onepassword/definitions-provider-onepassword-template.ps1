#region PROVIDER DEFINITIONS

param(
    [switch]$MinimumDefinitions
)

if ($MinimumDefinitions) {
    $root = $PSScriptRoot -replace "\\definitions",""
    Invoke-Command  -ScriptBlock { . $root\definitions.ps1 -MinimumDefinitions }
}
else {
    . $PSScriptRoot\classes.ps1
}

$Provider = $null
$Provider = $global:Catalog.Provider."OnePassword"
$Provider.Config = @{}

# $env:OP_SERVICE_ACCOUNT_TOKEN = "<op_service_account_token>"
$env:OP_SERVICE_ACCOUNT_TOKEN = "ops_eyJzaWduSW5BZGRyZXNzIjoiZGF0YTRhY3Rpb24uMXBhc3N3b3JkLmNvbSIsInVzZXJBdXRoIjp7Im1ldGhvZCI6IlNSUGctNDA5NiIsImFsZyI6IlBCRVMyZy1IUzI1NiIsIml0ZXJhdGlvbnMiOjY1MDAwMCwic2FsdCI6Im9URW9Pb2p6dDVCRDFnaUJKUU8yeEEifSwiZW1haWwiOiJ0aWY2eWdwbDR5N3lvQDFwYXNzd29yZHNlcnZpY2VhY2NvdW50cy5jb20iLCJzcnBYIjoiN2FhNjEzZGMxNzBmZWYwMzQzZWIzM2IzYTdkZTUwYmM5MmZkY2Q4MTdkNjhkZDA1NjEzZTVjODg1YzhkZGJmYyIsIm11ayI6eyJhbGciOiJBMjU2R0NNIiwiZXh0Ijp0cnVlLCJrIjoiUjlfV3dPZ2lRb2wzX1RwOENhOGZMeFF1Z053NDNuWHVoQmlKaHZuejltSSIsImtleV9vcHMiOlsiZW5jcnlwdCIsImRlY3J5cHQiXSwia3R5Ijoib2N0Iiwia2lkIjoibXAifSwic2VjcmV0S2V5IjoiQTMtOEpaU0xMLTZHUlRNVi1aRFg3TC1NWTNUWC01SzU5Ti1NUVQ4USIsInRocm90dGxlU2VjcmV0Ijp7InNlZWQiOiIwYzk4MDYyN2VkNDgyMjFhMDVhMWYzMmJlMWY0YzQyZWUzZmFmZjgyZjRlZjdiYzlkMjdiNWU0M2NhYWY4YTkxIiwidXVpZCI6IkpCT1pOTFc2VU5DWkpERUNYVzdPN0pUSzVJIn0sImRldmljZVV1aWQiOiJ5c3k3cnV6NDNldnBibWU0b2g3bmV3M2oyZSJ9"
$env:OP_FORMAT = "json"

return $Provider

#endregion PROVIDER DEFINITIONS