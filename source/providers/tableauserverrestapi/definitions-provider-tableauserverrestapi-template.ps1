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
$Provider = $global:Catalog.Provider.TableauServerRestApi

$Provider.Config = @{}
$Provider.Config += @{

    Defaults = @{

        Permissions = @{
            
            Workbook = @(
                "AddComment:Allow","AddComment:Deny",
                "ChangeHierarchy:Allow","ChangeHierarchy:Deny",
                "ChangePermissions:Allow","ChangePermissions:Deny",
                "Delete:Allow","Delete:Deny",
                "ExportData:Allow","ExportData:Deny",
                "ExportImage:Allow","ExportImage:Deny",
                "ExportXml:Allow","ExportXml:Deny",
                "Filter:Allow","Filter:Deny",
                "Read:Allow","Read:Deny",
                "ShareView:Allow","ShareView:Deny",
                "ViewComments:Allow","ViewComments:Deny",
                "ViewUnderlyingData:Allow","ViewUnderlyingData:Deny",
                "WebAuthoring:Allow","WebAuthoring:Deny",
                "Write:Allow","Write:Deny",
                "RunExplainData:Allow","RunExplainData:Deny",
                "CreateRefreshMetrics:Allow","CreateRefreshMetrics:Deny" 
            )

            View = @(
                "AddComment:Allow","AddComment:Deny",
                "ChangePermissions:Allow","ChangePermissions:Deny",
                "Delete:Allow","Delete:Deny",
                "ExportData:Allow","ExportData:Deny",
                "ExportImage:Allow","ExportImage:Deny",
                "ExportXml:Allow","ExportXml:Deny",
                "Filter:Allow","Filter:Deny",
                "Read:Allow","Read:Deny",
                "ShareView:Allow","ShareView:Deny",
                "ViewComments:Allow","ViewComments:Deny",
                "ViewUnderlyingData:Allow","ViewUnderlyingData:Deny",
                "WebAuthoring:Allow","WebAuthoring:Deny",
                "Write:Allow","Write:Deny"
            )

            DataSource = @(
                "ChangePermissions:Allow","ChangePermissions:Deny",
                "Connect:Allow","Connect:Deny",
                "Delete:Allow","Delete:Deny",
                "ExportXml:Allow","ExportXml:Deny",
                "Read:Allow","Read:Deny",
                "Write:Allow","Write:Deny"
            )

            Flow = @(
                "ChangeHierarchy:Allow","ChangeHierarchy:Deny",
                "ChangePermissions:Allow","ChangePermissions:Deny",
                "Delete:Allow","Delete:Deny",
                "ExportXml:Allow","ExportXml:Deny",
                "Execute:Allow","Execute:Deny",
                "Read:Allow","Read:Deny",
                "WebAuthoring:Allow","WebAuthoring:Deny",
                "Write:Allow","Write:Deny"
            )

            DataRole = @()
            Database = @()
            Metric = @()
            Lens = @()

        }

    }

}

return $Provider

#endregion PROVIDER DEFINITIONS