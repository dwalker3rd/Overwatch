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
                "Write:Allow","Write:Deny",
                "ChangeHierarchy:Allow","ChangeHierarchy:Deny",
                "SaveAs:Allow", "SaveAs:Deny"
            )

            Flow = @(
                "Read:Allow","Read:Deny",
                "Write:Deny","Write:Allow",
                "Delete:Deny","Delete:Allow",
                "ChangePermissions:Deny","ChangePermissions:Allow",
                "ExportXml:Allow","ExportXml:Deny",
                "ChangeHierarchy:Deny","ChangeHierarchy:Allow",
                "Execute:Allow","Execute:Deny",
                "WebAuthoringForFlows:Allow","WebAuthoringForFlows:Deny"
            )

            DataRole = @(
                "ChangePermissions:Allow","ChangePermissions:Deny",
                "Delete:Allow","Delete:Deny",
                "Read:Allow","Read:Deny",
                "Write:Allow","Write:Deny",
                "ChangeHierarchy:Allow","ChangeHierarchy:Deny",
                "SaveAs:Allow", "SaveAs:Deny"
            )

            Database = @(
                "ChangePermissions:Allow","ChangePermissions:Deny",
                "Read:Allow","Read:Deny",
                "Write:Allow","Write:Deny",
                "ChangeHierarchy:Allow","ChangeHierarchy:Deny"
            )

            Metric = @(
                "ChangePermissions:Allow","ChangePermissions:Deny",
                "Delete:Allow","Delete:Deny",
                "Read:Allow","Read:Deny",
                "Write:Allow","Write:Deny",
                "ChangeHierarchy:Allow","ChangeHierarchy:Deny"                
            )
            
            Lens = @(
                "ChangePermissions:Allow","ChangePermissions:Deny",
                "Delete:Allow","Delete:Deny",
                "Read:Allow","Read:Deny",
                "Write:Allow","Write:Deny",
                "ChangeHierarchy:Allow","ChangeHierarchy:Deny"                
            )

        }

    }

}

return $Provider

#endregion PROVIDER DEFINITIONS