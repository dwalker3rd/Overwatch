#region DEFINITIONS

$WorkbookPermissions = @(
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

$ViewPermissions = @(
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

$DataSourcePermissions = @(
    "ChangePermissions:Allow","ChangePermissions:Deny",
    "Connect:Allow","Connect:Deny",
    "Delete:Allow","Delete:Deny",
    "ExportXml:Allow","ExportXml:Deny",
    "Read:Allow","Read:Deny",
    "Write:Allow","Write:Deny"
)

$FlowPermissions = @(
    "ChangeHierarchy:Allow","ChangeHierarchy:Deny",
    "ChangePermissions:Allow","ChangePermissions:Deny",
    "Delete:Allow","Delete:Deny",
    "ExportXml:Allow","ExportXml:Deny",
    "Execute:Allow","Execute:Deny",
    "Read:Allow","Read:Deny",
    "WebAuthoring:Allow","WebAuthoring:Deny",
    "Write:Allow","Write:Deny"
)

#endregion DEFINITIONS
#region CONFIG

$EndpointVersioningType = @{
    RestApiVersioning = "RestApiVersioning"
    PerResourceVersioning = "PerResourceVersioning"
}
$EndpointVersioningType.Default = $EndpointVersioningType.RestApiVersioning

function Get-VersioningType {
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Method
    )
    return $global:tsRestApiConfig.Method.$Method.VersioningType ?? $EndpointVersioningType.Default
}

function IsRestApiVersioning {
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Method
    )
    return (Get-VersioningType -Method $Method) -eq $EndpointVersioningType.RestApiVersioning
}

function IsPerResourceVersioning {
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Method
    )
    return (Get-VersioningType -Method $Method) -eq $EndpointVersioningType.PerResourceVersioning
}

function Get-TSServerType {
    param(
        [Parameter(Mandatory=$false,Position=0)][string]$Server
    )
    $serverType = $global:tsRestApiConfig.Platform.Id ?? "TableauServer"
    if (![string]::IsNullOrEmpty($Server)) {
        if (IsTableauCloud -Server $Server) {
            $serverType = "TableauCloud"
        }
    }
    return $serverType
}

function IsTableauCloud {
    param(
        [Parameter(Mandatory=$false,Position=0)][string]$Server
    )
    $_isTableauCloud = $false
    if (![string]::IsNullOrEmpty($Server)) {
        $_isTableauCloud = $Server -like "*online.tableau.com"
    }
    elseif (![string]::IsNullOrEmpty($global:tsRestApiConfig.Platform.id)) {
        $_isTableauCloud = $global:tsRestApiConfig.Platform.Id -eq "TableauCloud"
    }
    return $_isTableauCloud
}

function IsPlatformServer {
    param(
        [Parameter(Mandatory=$false,Position=0)][string]$Server
    )
    return $Server -eq "localhost" -or $Server -eq $env:COMPUTERNAME -or $Server -eq $global:Platform.Uri.Host
}

function global:Initialize-TSRestApiConfiguration {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Server = $global:Platform.Uri.Host,
        [Parameter(Mandatory=$false)][Alias("Site")][string]$ContentUrl = "",
        [Parameter(Mandatory=$false)][string]$Credentials = "localadmin-$($Platform.Instance)",
        [switch]$Reset
    )

    if ($Reset) {
        $global:tsRestApiConfig = @{}
    }

    $global:tsRestApiConfig = @{
        Server = $Server ? $Server : $global:Platform.Uri.Host
        Credentials = $Credentials
        Token = $null
        SiteId = $null
        ContentUrl = $ContentUrl
        # ContentType = "application/xml;charset=utf-8"
        UserId = $null
        SpecialAccounts = @("guest","tableausvc","TabSrvAdmin","alteryxsvc")
        SpecialGroups = @("All Users")
        SpecialMethods = @("ServerInfo","Login")
    }

    $global:tsRestApiConfig.RestApiVersioning = @{
        ApiUri = ""
        ApiVersion = "3.15"
        ContentType = "application/xml; charset=utf-8"
        Headers = @{
            "Accept" = "*/*"
            "X-Tableau-Auth" = $global:tsRestApiConfig.Token
        }
    }
    $global:tsRestApiConfig.RestApiVersioning.ApiUri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)"
    $global:tsRestApiConfig.RestApiVersioning.Headers."Content-Type" = $global:tsRestApiConfig.RestApiVersioning.ContentType

    $global:tsRestApiConfig.PerResourceVersioning = @{
        ApiUri = ""
        ApiVersion = "-"
        ContentType = "application/vnd.<ResourceString>+json; charset=utf-8"
        Headers = @{
            "Accept" = "*/*"
            "X-Tableau-Auth" = $global:tsRestApiConfig.Token
        }
    }
    $global:tsRestApiConfig.PerResourceVersioning.ApiUri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.PerResourceVersioning.ApiVersion)"
    $global:tsRestApiConfig.PerResourceVersioning.Headers."Content-Type" = $global:tsRestApiConfig.PerResourceVersioning.ContentType
    
    $global:tsRestApiConfig.Method = @{
        Login = @{
            Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/auth/signin"
            HttpMethod = "POST"
            Body = "<tsRequest><credentials name='<0>' password='<1>'><site contentUrl='<2>'/></credentials></tsRequest>"
            Response = @{Keys = "credentials"}
        } 
        ServerInfo = @{
            Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/serverinfo"
            HttpMethod = "GET"
            Response = @{Keys = "serverinfo"}
        }
    }

    $creds = Get-Credentials $global:tsRestApiConfig.Credentials

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method Login -Params @($creds.UserName,$creds.GetNetworkCredential().Password,$global:tsRestApiConfig.ContentUrl)
    if ($responseError) {
        if ($responseError.code) {
            throw "$($responseError.code) ($($responseError.summary)): $($responseError.detail)"
        }
        else {
            throw $responseError
        }
    }

    $global:tsRestApiConfig.Token = $response.token
    $global:tsRestApiConfig.SiteId = $response.site.id
    $global:tsRestApiConfig.ContentUrl = $response.site.contentUrl
    $global:tsRestApiConfig.UserId = $response.user.id 

    $global:tsRestApiConfig.RestApiVersioning.Headers."X-Tableau-Auth" = $global:tsRestApiConfig.Token
    $global:tsRestApiConfig.PerResourceVersioning.Headers."X-Tableau-Auth" = $global:tsRestApiConfig.Token

    $serverInfo = Get-TsServerInfo

    if (IsPlatformServer $global:tsRestApiConfig.Server) {
        $global:tsRestApiConfig.Platform = $global:Platform
    }
    else {
        $global:tsRestApiConfig.Platform = $global:Catalog.Platform.(Get-TSServerType -Server $Server) | Copy-Object
        $global:tsRestApiConfig.Platform.Uri = [System.Uri]::new("https://$Server")
        $global:tsRestApiConfig.Platform.Domain = $Server.Split(".")[-1]
        $global:tsRestApiConfig.Platform.Instance = "$($Server.Replace(".","-"))"
    }
    $global:tsRestApiConfig.Platform.Api.TsRestApiVersion = $serverinfo.restApiVersion
    $global:tsRestApiConfig.Platform.Version = $serverinfo.productVersion.InnerText
    $global:tsRestApiConfig.Platform.Build = $serverinfo.productVersion.build
    $global:tsRestApiConfig.Platform.DisplayName = $global:tsRestApiConfig.Platform.Name + " " + $global:tsRestApiConfig.Platform.Version

    $platformInfo = @{
        Version=$global:Platform.Version
        Build=$global:Platform.Build
        TsRestApiVersion=$global:Platform.Api.TsRestApiVersion
    }
    $platformInfo | Write-Cache platforminfo

    Update-TSRestApiMethods
    
    return

}
Set-Alias -Name tsRestApiInit -Value Initialize-TSRestApiConfiguration -Scope Global

function global:Update-TSRestApiMethods {

    [CmdletBinding()]
    param ()

    $global:tsRestApiConfig.Method = @{

        #region SESSION METHODS

            Login = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/auth/signin"
                HttpMethod = "POST"
                Body = "<tsRequest><credentials name='<0>' password='<1>'><site contentUrl='<2>'/></credentials></tsRequest>"
                Response = @{Keys = "credentials"}
            } 
            GetCurrentSession = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sessions/current"
                HttpMethod = "GET"
                Response = @{Keys = "session"}
            }
            Logout = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/auth/signout"
                HttpMethod = "POST"
            }

        #endregion SESSION METHODS
        #region SERVER METHODS

            ServerInfo = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/serverinfo"
                HttpMethod = "GET"
                Response = @{Keys = "serverinfo"}
            }
            GetDomains = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/domains"
                HttpMethod = "GET"
                Response = @{Keys = "domainList"}
            }

        #endregion SERVER METHODS
        #region GROUP METHODS

            GetGroups = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/groups"
                HttpMethod = "GET"
                Response = @{Keys = "groups.group"}
            }
            AddGroupToSite = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/groups"
                HttpMethod = "POST"
                Body = "<tsRequest><group name='<0>'/></tsRequest>"
                Response = @{Keys = "group"}
            }
            RemoveGroupFromSite = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/groups/<0>"
                HttpMethod = "DELETE"
                Response = @{Keys = "group"}
            }
            GetGroupMembership = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/groups/<0>/users"
                HttpMethod = "GET"
                Response = @{Keys = "users.user"}
            }
            AddUserToGroup = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/groups/<0>/users"
                HttpMethod = "POST"
                Body = "<tsRequest><user id='<1>'/></tsRequest>"
                Response = @{Keys = "user"}
            }
            RemoveUserFromGroup = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/groups/<0>/users/<1>"
                HttpMethod = "DELETE"
                Response = @{Keys = ""}
            }

        #endregion GROUP METHODS
        #region SITE METHODS

            SwitchSite = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/auth/switchSite"
                HttpMethod = "POST"
                Body = "<tsRequest><site contentUrl='<0>'/></tsRequest>"
                Response = @{Keys = "credentials"}
            } 
            GetSites = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites"
                HttpMethod = "GET"
                Response = @{Keys = "sites.site"}
            }
            GetSite = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)"
                HttpMethod = "GET"
                Response = @{Keys = "site"}
            }

        #endregion SITE METHODS
        #region USER METHODS

            GetUsers = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/users?fields=_all_"
                HttpMethod = "GET"
                Response = @{Keys = "users.user"}
            }
            GetUser = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/users/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "user"}
            }
            AddUser = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/users"
                HttpMethod = "POST"
                Body = "<tsRequest><user name='<0>' siteRole='<1>' /></tsRequest>"
                Response = @{Keys = "user"}
            }
            RemoveUser = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/users/<0>"
                HttpMethod = "DELETE"
                Response = @{Keys = ""}
            }
            UpdateUser = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/users/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><user fullName=`"<1>`" email=`"<2>`" siteRole=`"<3>`" /></tsRequest>"
                Response = @{Keys = "user"}
            }
            UpdateUserPassword = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/users/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><user password='<1>' /></tsRequest>"
                Response = @{Keys = "user"}
            }
            GetUserMembership = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/users/<0>/groups"
                HttpMethod = "GET"
                Response = @{Keys = "groups.group"}
            }

        #endregion USER METHODS
        #region PROJECT METHODS 
            
            GetProjects = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/projects"
                HttpMethod = "GET"
                Response = @{Keys = "projects.project"}
            }
            GetProjectPermissions = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }
            GetProjectDefaultPermissions = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/default-permissions/<1>"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }
            AddProjectPermissions = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }
            AddProjectDefaultPermissions = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/default-permissions/<1>"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><2></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }
            RemoveProjectPermissions = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/permissions/<1>/<2>/<3>/<4>"
                HttpMethod = "DELETE"
                Response = @{Keys = "permissions"}
            }
            RemoveProjectDefaultPermissions = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/default-permissions/<1>/<2>/<3>/<4>/<5>"
                HttpMethod = "DELETE"
                Response = @{Keys = "permissions"}
            }

        #endregion PROJECT METHODS
        #region WORKBOOK METHODS

            GetWorkbooks = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks"
                HttpMethod = "GET"
                Response = @{Keys = "workbooks.workbook"}
            }
            GetWorkbook = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "workbook"}
            }
            UpdateWorkbook = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><workbook name='<1>' ><project id='<2>' /><owner id='<3>' /></workbook></tsRequest>"
                Response = @{Keys = "workbook"}
            }
            GetWorkbookRevisions = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/revisions"
                HttpMethod = "GET"
                Response = @{Keys = "revisions.revision"}
            }
            GetWorkbookRevision = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/revisions/<1>"
                HttpMethod = "GET"
                Response = @{Keys = "revisions.revision"}
                Revision = "<1>"
            }
            GetWorkbookPermissions = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }   
            AddWorkbookPermissions = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }
            GetWorkbookConnections = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/connections"
                HttpMethod = "GET"
                Response = @{Keys = "connections.connection"}
            }

        #endregion WORKBOOK METHODS
        #region VIEW METHODS 

            GetViewsForSite = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/views"
                HttpMethod = "GET"
                Response = @{Keys = "views.view"}
            }
            GetViewsForWorkbook = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/views"
                HttpMethod = "GET"
                Response = @{Keys = "views.view"}
            }
            GetViewPermissions = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/views/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }   
            AddViewPermissions = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/views/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }

        #endregion VIEW METHODS 
        #region DATASOURCE METHODS 

            GetDataSource = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "datasource"}
            }
            GetDataSources = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/datasources"
                HttpMethod = "GET"
                Response = @{Keys = "datasources.datasource"}
            }
            UpdateDataSource = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><datasource name='<1>' ><project id='<2>' /><owner id='<3>' /></datasource></tsRequest>"
                Response = @{Keys = "datasource"}
            }
            GetDatasourcePermissions = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }
            AddDataSourcePermissions = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }
            GetDataSourceRevisions = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>/revisions"
                HttpMethod = "GET"
                Response = @{Keys = "revisions.revision"}
            }
            GetDatasourceRevision = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>/revisions/<1>"
                HttpMethod = "GET"
                Response = @{Keys = "revisions.revision"}
                Revision = "<1>"
            }
            GetDataSourceConnections = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>/connections"
                HttpMethod = "GET"
                Response = @{Keys = "connections.connection"}
            }

        #endregion DATASOURCE METHODS
        #region FLOW METHODS

            GetFlows = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/flows"
                HttpMethod = "GET"
                Response = @{Keys = "flows.flow"}
            }
            GetFlow = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/flows/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "flow"}
            }
            UpdateFlow = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/flows/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><flow name='<1>' ><project id='<2>' /><owner id='<3>' /></flow></tsRequest>"
                Response = @{Keys = "flow"}
            }
            GetFlowPermissions = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/flows/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }
            AddFlowPermissions = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/flows/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }

        #endregion FLOW METHODS          
        #region METRIC METHODS

            GetMetrics = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/metrics"
                HttpMethod = "GET"
                Response = @{Keys = "metrics.metric"}
            }
            GetMetric = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/metrics/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "metrics.metric"}
            }
            UpdateMetric = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/metrics/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><metric name='<1>' ><project id='<2>' /><owner id='<3>' /></metric></tsRequest>"
                Response = @{Keys = "metric"}
            }

        #endregion METRIC METHODS
        #region COLLECTION METHODS

            GetCollections = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/collections/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "collections.collection"}
            }

        #endregion METRIC METHODS
        #region FAVORITE METHODS

            GetFavorites = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/favorites/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "favorites.favorite"}
            }
            AddFavorites = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/favorites/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><favorite label='<1>'><<2> id='<3>'/></favorite></tsRequest>"
                Response = @{Keys = "favorites.favorite"}
            }

        #endregion FAVORITE METHODS
        #region SCHEDULES

            GetSchedules = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/schedules"
                HttpMethod = "GET"
                Response = @{Keys = "schedules.schedule"}
            }
            GetSchedule = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/schedules/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "schedule"}
            }
        
        #endregion SCHEDULES
        #region SUBSCRIPTIONS

            GetSubscriptions = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/subscriptions"
                HttpMethod = "GET"
                Response = @{Keys = "subscriptions.subscription"}
            }
            GetSubscription = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/subscriptions/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "subscription"}
            }

        #endregion SUBSCRIPTIONS
        #region NOTIFICATIONS
            
            GetDataAlerts = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/dataAlerts"
                HttpMethod = "GET"
                Response = @{Keys = "dataAlerts.dataAlert"}
            }
            GetWebhooks = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/webhooks"
                HttpMethod = "GET"
                Response = @{Keys = "webhooks.webhook"}
            }
            GetWebhook = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/webhooks/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "webhook"}
            }
            GetUserNotificationPreferences = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/settings/notifications"
                HttpMethod = "GET"
                Response = @{Keys = "userNotificationsPreferences.userNotificationsPreference"}
            }

        #endregion NOTIFICATIONS
        #region ANALYTICS EXTENSIONS

            GetAnalyticsExtensionsConnectionsForSite = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/-/settings/site/extensions/analytics/connections"
                HttpMethod = "GET"
                Response = @{Keys = "connectionList"}
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
                VersioningType = $EndpointVersioningType.PerResourceVersioning
            }
            GetAnalyticsExtensionsEnabledStateForSite = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/-/settings/site/extensions/analytics"
                HttpMethod = "GET"
                Response = @{Keys = "enabled"}
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
                VersioningType = $EndpointVersioningType.PerResourceVersioning
            }  

        #endregion ANALYTICS EXTENSIONS
        #region DASHBOARD EXTENSIONS

            GetDashboardExtensionSettingsForServer = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/-/settings/server/extensions/dashboard"
                HttpMethod = "GET"
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
                VersioningType = $EndpointVersioningType.PerResourceVersioning
            } 
            GetBlockedDashboardExtensionsForServer = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/-/settings/server/extensions/dashboard/blockListItems"
                HttpMethod = "GET"
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
                VersioningType = $EndpointVersioningType.PerResourceVersioning
            }  
            GetDashboardExtensionSettingsForSite = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/-/settings/site/extensions/dashboard"
                HttpMethod = "GET"
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
                VersioningType = $EndpointVersioningType.PerResourceVersioning
            } 
            GetAllowedDashboardExtensionsForSite = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/-/settings/site/extensions/dashboard/safeListItems"
                HttpMethod = "GET"
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
                VersioningType = $EndpointVersioningType.PerResourceVersioning
            }

        #endregion DASHBOARD EXTENSIONS
        #region CONNECTED APPLICATIONS

            GetConnectedApplications = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/connected-applications"
                HttpMethod = "GET"
                Response = @{Keys = "connectedApplications.connectedApplication"}
            }
            GetConnectedApplication = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/connected-applications/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "connectedApplications.connectedApplication"}
            }

        #endregion CONNECTED APPLICATIONS
        #region PUBLISH

            PublishWorkbook = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks?overwrite=true"
                HttpMethod = "POST"
                Response = @{Keys = "workbook"}
            }
            PublishDatasource = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/datasources?overwrite=true"
                HttpMethod = "POST"
                Response = @{Keys = "datasource"}
            }
            InitiateFileUpload = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/fileUploads/"
                HttpMethod = "POST"
                Response = @{Keys = "fileUpload.uploadSessionId"}
            }
            AppendToFileUpload = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/fileUploads/<0>"
                HttpMethod = "PUT"
                Response = @{Keys = "fileUpload"}
            }
            PublishWorkbookMultipart = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks?uploadSessionId=<0>&workbookType=<1>&overwrite=<2>"
                HttpMethod = "POST"
                Response = @{Keys = "workbook"}
            }
            PublishDatasourceMultipart = @{
                Uri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/datasources?uploadSessionId=<0>&datasourceType=<1>&overwrite=<2>"
                HttpMethod = "POST"
                Response = @{Keys = "datasource"}
            }

        #endregion PUBLISH

    }

    return
}

#endregion CONFIG
#region INVOKE

function global:Invoke-TSRestApiMethod {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Method,
        [Parameter(Mandatory=$false,Position=1)][string[]]$Params,
        [Parameter(Mandatory=$false)][ValidateRange(1,1000)][int]$PageNumber = 1,
        [Parameter(Mandatory=$false)][ValidateRange(1,1000)][int]$PageSize = 100,
        [Parameter(Mandatory=$false)][string]$Filter,
        [Parameter(Mandatory=$false)][int]$TimeoutSec = 0
    )

    if ($Method -notin $global:tsRestApiConfig.SpecialMethods -and !$global:tsRestApiConfig.Token) {

        $creds = Get-Credentials $global:tsRestApiConfig.Credentials

        $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method Login -Params @($creds.UserName,$creds.GetNetworkCredential().Password,$global:tsRestApiConfig.ContentUrl)
        if (!$responseError) {
            $global:tsRestApiConfig.Token = $response.token
            $global:tsRestApiConfig.SiteId = $response.site.id
            $global:tsRestApiConfig.ContentUrl = $response.site.contentUrl
            $global:tsRestApiConfig.UserId = $response.user.id 
        }
        else {
            $responseError = @{
                code = "401002"
                summary = "Unauthorized Access"
                detail = "Invalid authentication credentials were provided"
            }
            return $null, $null, $responseError
        }
    }

    $responseRoot = (IsRestApiVersioning -Method $Method) ? "tsResponse" : $null
    
    $pageFilter = "pageNumber=$($PageNumber)&pageSize=$($PageSize)"
    $_filter = $Filter ? "filter=$($Filter)&$($pageFilter)" : "$($pageFilter)"

    $httpMethod = $global:tsRestApiConfig.Method.$Method.HttpMethod

    $uri = "$($global:tsRestApiConfig.Method.$Method.Uri)"
    $questionMarkOrAmpersand = $uri.Contains("?") ? "&" : "?"
    $uri += (IsRestApiVersioning -Method $Method) -and $httpMethod -eq "GET" ? "$($questionMarkOrAmpersand)$($_filter)" : $null

    $body = $global:tsRestApiConfig.Method.$Method.Body

    $headers = $global:tsRestApiConfig.(Get-VersioningType -Method $Method).Headers | Copy-Object
    $headers."Content-Type" = $headers."Content-Type".Replace("<ResourceString>",$global:tsRestApiConfig.Method.$Method.ResourceString)
    foreach ($key in $global:tsRestApiConfig.Method.$Method.Headers.Keys) {
        if ($key -in $headers.Keys) { $headers.Remove($key) }
        $headers.$key = $global:tsRestApiConfig.Method.$Method.Headers.$key
    }

    $keys = $global:tsRestApiConfig.Method.$Method.Response.Keys
    # $tsObjectName = $keys ? $keys.split(".")[-1] : "response"

    for ($i = 0; $i -lt $Params.Count; $i++) {
        $uri = $uri -replace "<$($i)>",$Params[$i]
        $body = $body -replace "<$($i)>",$Params[$i]
        $keys = $keys -replace "<$($i)>",$Params[$i]
    } 
    
    if ($headers.ContentLength) { $headers.ContentLength = $body.Length }
    
    try {
        $response = Invoke-RestMethod -Uri $uri -Method $httpMethod -Headers $headers -Body $body -ContentType $global:tsRestApiConfig.(Get-VersioningType -Method $Method).ContentType -TimeoutSec $TimeoutSec -ResponseHeadersVariable responseHeaders
        if (IsRestApiVersioning -Method $Method) {
            $responseError = $response.$responseRoot.error 
        }
        else {
            if ($response.httpErrorCode) {
                $responseError = @{
                    code = $response.httpErrorCode
                    detail = $response.message
                }
            }
        }
    }
    catch {
        $responseError = $_.ErrorDetails.Message ?? $_.Exception.Message
    }

    if ($responseError) {
        return $response, $null, $responseError
    }

    $pagination = [ordered]@{
        PageNumber = $PageNumber
        PageSize = $PageSize
        CountThisPage = 0
        TotalAvailable = [int]($response.$responseRoot.pagination.totalAvailable)
        TotalRemaining = 0
        TotalReturned = 0
        IsLastPage = $false
    }
    $pagination.TotalRemaining = $pagination.TotalAvailable -gt ($PageNumber * $PageSize) ? ($pagination.TotalAvailable - ($PageNumber * $PageSize)) : 0
    $pagination.IsLastPage = $pagination.TotalRemaining -eq 0

    # $response = $response | Copy-Object
    $keys = $keys ? "$($responseRoot)$($responseRoot ? "." : $null)$($keys)" : $responseRoot
    if ($keys) {
        foreach ($key in $keys.split(".")) {
            $response = $response.$key
        }
    }

    $pagination.CountThisPage = $response.Count
    $pagination.TotalReturned = ((($PageNumber - 1) * $PageSize) + $pagination.CountThisPage)

    return $response, $pagination, $responseError

}

#endregion INVOKE
#region DOWNLOAD

function global:Download-TSObject {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Method,
        [Parameter(Mandatory=$true)][Alias("Workbook","Datasource","Flow")][object]$InputObject,
        [Parameter(Mandatory=$false)][string[]]$Params = @($InputObject.Id),
        [Parameter(Mandatory=$false)][int]$TimeoutSec = 0
    )

    if ($Method -notin $global:tsRestApiConfig.SpecialMethods -and !$global:tsRestApiConfig.Token) {
        $responseError = @{
            code = "401002"
            summary = "Unauthorized Access"
            detail = "Invalid authentication credentials were provided"
        }
        $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
        Write-Log -Message $errorMessage -EntryType "Error" -Action "TSRestApiMethod" -Target $Method -Status "Error"
        return $null, $null, $responseError
    }

    if (!$InputObject -and !$Params) {
        throw "ERROR: `"InputObject`" or `"Params`" parameters must be specified"
    }

    $objectType = $global:tsRestApiConfig.Method.$Method.Response.Keys.Split(".")[-1]

    $projectPath = ""
    $projects = Get-TSProjects
    $project = $projects | Where-Object {$_.id -eq $InputObject.project.id}
    do {
        $projectName = $project.Name -replace $global:RegexPattern.Download.InvalidFileNameChars, ""
        $projectPath = $projectName + ($projectPath ? "\" : $null) + $projectPath
        $project = $projects | Where-Object {$_.id -eq $project.parentProjectId}
    } until (!$project)

    $contentUrl = ![string]::IsNullOrEmpty($global:tsRestApiConfig.ContentUrl) ? $global:tsRestApiConfig.ContentUrl : "default"

    $httpMethod = $global:tsRestApiConfig.Method.$Method.HttpMethod
    $uri = "$($global:tsRestApiConfig.Method.$Method.Uri)/content"
    $revision = $global:tsRestApiConfig.Method.$Method.Revision 

    for ($i = 0; $i -lt $Params.Count; $i++) {
        $uri = $uri -replace "<$($i)>",$Params[$i]
        $revision = $revision -replace "<$($i)>",$Params[$i]
    }
    
    $headers = $global:tsRestApiConfig.(Get-VersioningType -Method $Method).Headers | Copy-Object
    $headers."Content-Type" = $headers."Content-Type".Replace("<ResourceString>",$global:tsRestApiConfig.Method.$Method.ResourceString)

    $tempOutFileDirectory = "$($global:Location.Root)\Data\$($global:tsRestApiConfig.Platform.Instance)\.export\$contentUrl\.temp"
    if (!(Test-Path $tempOutFileDirectory)) { New-Item -ItemType Directory -Path $tempOutFileDirectory | Out-Null }
    $tempOutFile = "$tempOutFileDirectory\$($InputObject.id)"
    Remove-Item -Path $tempOutFile -Force -ErrorAction SilentlyContinue

    try {
        $response = Invoke-RestMethod -Uri $uri -Method $httpMethod -Headers $headers -TimeoutSec $TimeoutSec -SkipCertificateCheck -SkipHttpErrorCheck -OutFile $tempOutFile -ResponseHeadersVariable responseHeaders
        $responseError = $null
        if (IsRestApiVersioning -Method $Method) {
            if ($response.$responseRoot.error) { return @{ error = $response.$responseRoot.error } }
        }
        else {
            if ($response.httpErrorCode) {
                return @{ error = [System.Collections.Specialized.OrderedDictionary]@{ code = $response.httpErrorCode; detail = $response.message } }
            }
        }
    }
    catch {
        return @{ error = $_.Exception.Message }
    }

    if ([string]::IsNullOrEmpty($responseHeaders."Content-Disposition")) {
        return @{ error = [System.Collections.Specialized.OrderedDictionary]@{ code = 404; summary = "Not Found"; detail = "$((Get-Culture).TextInfo.ToTitleCase($objectType)) download failed" }  }
    }      

    $contentDisposition = $responseHeaders."Content-Disposition".Split("; ")
    $contentDispositionFileName = $contentDisposition[1].Split("=")[1].Replace("`"","")
    $outFileNameLeafBase = Split-Path $contentDispositionFileName -LeafBase
    $outFileExtension = Split-Path $contentDispositionFileName -Extension
    $outFileName = $outFileNameLeafBase + ($revision ? ".rev$revision" : $null) + $outFileExtension
    $outFileDirectory = "$($global:Location.Root)\Data\$($global:tsRestApiConfig.Platform.Instance)\.export\$contentUrl\$projectPath$($revision ? "\$contentDispositionFileName.revisions" : $null)"
    $outFileDirectory = $outFileDirectory -replace "[<>|]", "-"
    if (!(Test-Path $outFileDirectory)) { New-Item -ItemType Directory -Path $outFileDirectory | Out-Null }
    $outFile = "$outFileDirectory\$outFileName"

    Remove-Item -Path $outFile -Force -ErrorAction SilentlyContinue
    try {
        Move-Item -Path $tempOutFile -Destination $outFile -PassThru -Force
    }
    catch {
        return @{ error = $_.Exception.Message }
    }
    if (!(Test-Path -Path $outFile)) {
        return @{ error = "Failed to move $((Get-Culture).TextInfo.ToTitleCase($objectType)) temp file to target directory" }
    }

    return @{ outFile = $outFile }

}

#endregion DOWNLOAD
#region PUBLISH

    function global:Publish-TSContent {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true,Position=0)][string]$Path,
            [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectId,
            [Parameter(Mandatory=$false)][string]$Name = (Split-Path $Path -LeafBase),
            [Parameter(Mandatory=$false)][ValidateSet("twb","twbx","tde","tds","tdsx","hyper","tfl","tflx")][string]$Extension = ((Split-Path $Path -Extension).TrimStart(".")),
            [Parameter(Mandatory=$false)][switch]$Progress = $global:ProgressPreference -eq "Continue"
        )

        #region DEFINITIONS

            $uriBase = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)"
            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("X-Tableau-Auth", $global:tsRestApiConfig.Token)

            $fileName = $Name + "." + $Extension 
            $objectName = [string]::IsNullOrEmpty($Name) ? $Name : $Name
            
            $workbookExtensions = @("twb","twbx")
            $datasourceExtensions = @("tde","tds","tdsx","hyper")
            $flowExtensions = @("tfl","tflx")

            $Type = ""
            if ($Extension -in $workbookExtensions) { $Type = "workbook" }
            if ($Extension -in $datasourceExtensions) { $Type = "datasource" }
            if ($Extension -in $flowExtensions) { $Type = "flow" }

            $fileSize = (Get-ChildItem $Path).Length

        #endregion DEFINITIONS
        #region INITIATE FILE UPLOAD        

            $uploadSessionId = Invoke-TSMethod -Method InitiateFileUpload 

        #endregion INITIATE FILE UPLOAD
        #region APPEND TO FILE UPLOAD

            [console]::CursorVisible = $false

            $message =  "<Uploading $Type `'$fileName`' <.>58> PENDING$($emptyString.PadLeft(9," "))"
            Write-Host+ -Iff $Progress -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

            $chunkSize = 1mb
            $progressSizeInt = 1mb
            $progressSizeString = "mb"
            if ($fileSize/$progressSizeInt -le 1) {
                $progressSizeInt = 1kb
                $progressSizeString = "kb"
            }

            $chunk = New-Object byte[] $chunkSize
            $fileStream = [System.IO.File]::OpenRead($Path)

            $bytesReadTotal = 0
            $chunkCount = 1
            while ($bytesRead = $fileStream.Read($chunk, 0, $chunkSize)) {

                # track bytes read
                $bytesReadTotal += $bytesRead
                
                # multipart/form-data, string content
                $multipartContent = [System.Net.Http.MultipartFormDataContent]::new()
                $stringHeader = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new("form-data")
                $stringHeader.Name = "`"request_payload`""
                $stringContent = [System.Net.Http.StringContent]::new("")
                $stringContent.Headers.ContentDisposition = $stringHeader
                $stringContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("text/xml")
                $multipartContent.Add($stringContent)

                # multipart/form-data, byte array content
                $byteArrayHeader = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new("form-data")
                $byteArrayHeader.Name = "`"tableau_file`""
                $byteArrayHeader.FileName = "`"$objectName`""
                # adjust length of last chunk!
                $byteArrayContent = [System.Net.Http.ByteArrayContent]::new($chunk[0..($bytesRead-1)])
                $byteArrayContent.Headers.ContentDisposition = $byteArrayHeader
                $byteArrayContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")
                $multipartContent.Add($byteArrayContent)

                $body = $multipartContent

                # Content-Type header mod
                # tableau requires that the multipart/form-data payload be defined as multipart/mixed
                $contentType = ($body.headers | where-object {$_.key -eq "Content-Type"}).value -replace "form-data","mixed"
                $body.Headers.Remove("Content-Type") | Out-Null
                $body.Headers.Add("Content-Type",$contentType)

                $responseError = $null
                try {
                    $response = Invoke-RestMethod "$uriBase/fileUploads/$uploadSessionId" -Method 'PUT' -Headers $headers -Body $body
                    $responseError = $response.tsResponse.error
                }
                catch {
                    $responseError = $_.Exception.Message
                }
                finally {
                    $fileSizeString = "$([math]::Round($fileSize/$progressSizeInt,0))"
                    $fileSizeString = "$($fileSizeString.PadLeft($fileSizeString.Length))$progressSizeString"
                    $bytesReadTotalString = "$([math]::Round($bytesReadTotal/$progressSizeInt,0))"
                    $bytesReadTotalString = "$($bytesReadTotalString.PadLeft($fileSizeString.Length))$progressSizeString"
                }

                if ($responseError) {

                    $errorMessage = "Error at AppendToFileUpload (Chunk# $chunkCount): "
                    if ($responseError.code) {
                        $errorMessage += "$($responseError.code)$((IsRestApiVersioning -Method $Method) ? " $($responseError.summary)" : $null): $($responseError.detail)"
                    }
                    else {
                        $errorMessage += $responseError
                    }

                    $message = "$($emptyString.PadLeft(16,"`b"))FAILURE$($emptyString.PadLeft(16-$bytesUploaded.Length," "))"
                    Write-Host+ -Iff $Progress -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor Red
                    [console]::CursorVisible = $true

                    $fileStream.Close()

                    throw $errorMessage
                    
                }

                $message = "$($emptyString.PadLeft(16,"`b"))$bytesReadTotalString","/","$fileSizeString$($emptyString.PadLeft(16-($bytesReadTotalString.Length + 1 + $fileSizeString.Length)," "))"
                Write-Host+ -Iff $Progress -NoTrace -NoNewLine -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen,DarkGray,DarkGray

                $chunkCount++

            }

            $message = "$($emptyString.PadLeft(16,"`b"))$bytesReadTotalString","/","$fileSizeString$($emptyString.PadLeft(16-($bytesReadTotalString.Length + 1 + $fileSizeString.Length)," "))"
            Write-Host+ -Iff $Progress -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen,DarkGray,DarkGreen

            [console]::CursorVisible = $true

        #endregion APPEND TO FILE UPLOAD        
        #region FINALIZE UPLOAD

            # multipart/form-data, string content
            $multipartContent = [System.Net.Http.MultipartFormDataContent]::new()
            $stringHeader = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new("form-data")
            $stringHeader.Name = "`"request_payload`""
            $stringContent = [System.Net.Http.StringContent]::new("<tsRequest><$Type name=`"$objectName`"><project id=`"$ProjectId`"/></$Type></tsRequest>")
            $stringContent.Headers.ContentDisposition = $stringHeader
            $stringContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("text/xml")
            $multipartContent.Add($stringContent)

            $body = $multipartContent

            # Content-Type header mod
            # tableau requires that the multipart/form-data payload be defined as multipart/mixed
            $contentType = ($body.headers | where-object {$_.key -eq "Content-Type"}).value -replace "form-data","mixed"
            $body.Headers.Remove("Content-Type") | Out-Null
            $body.Headers.Add("Content-Type",$contentType)

            $responseError = $null
            try {
                $response = Invoke-RestMethod "$uriBase/$($Type)s?uploadSessionId=$uploadSessionId&$($Type)Type=$Extension&overwrite=true" -Method 'POST' -Headers $headers -Body $body
                $responseError = $response.tsResponse.error
            }
            catch {
                $responseError = $_.Exception.Message
            }
            finally {        
                $fileStream.Close()
            }

            if ($responseError) {
                $errorMessage = "Error at Publish$((Get-Culture).TextInfo.ToTitleCase($Type)): "
                if ($responseError.code) {
                    $errorMessage = "$($responseError.code)$((IsRestApiVersioning -Method $Method) ? " $($responseError.summary)" : $null): $($responseError.detail)"
                }
                else {
                    $errorMessage = $responseError
                }
                throw $errorMessage
            }

            return $response.tsResponse.$Type

        #endregion FINALIZE UPLOAD        

    }

#endregion PUBLISH
#region SESSION

function global:Connect-TableauServer {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Server = $global:Platform.Uri.Host,
        [Parameter(Mandatory=$false,Position=1)][Alias("Site")][string]$ContentUrl
    )

    Initialize-TSRestApiConfiguration $Server
    if ($ContentUrl) {Switch-TSSite $ContentUrl}

    return
}

function global:Get-TSCurrentSession {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method GetCurrentSession

}

function global:Disconnect-TableauServer {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Server = $global:Platform.Uri.Host
    )

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method Logout

    $global:tsRestApiConfig = @{
        SpecialAccounts = @("guest","tableausvc","TabSrvAdmin","alteryxsvc","pathdevsvc")
        SpecialGroups = @("All Users")
    }
    $global:tsRestApiConfig | Out-Null

    return
}

#endregion SESSION

#region SERVER

function global:Get-TSServerInfo {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method ServerInfo -TimeoutSec 60

}

#endregion SERVER

#region OBJECT

function global:Get-TSObjects {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Method,
        [Parameter(Mandatory=$false,Position=1)][string[]]$Params,
        [Parameter(Mandatory=$false)][ValidateRange(1,1000)][int]$PageNumber = 1,
        [Parameter(Mandatory=$false)][ValidateRange(1,1000)][int]$PageSize = 100,
        [Parameter(Mandatory=$false)][string]$Filter,
        [Parameter(Mandatory=$false)][int]$TimeoutSec = 0,
        [switch]$Download
    )

    $objects = @()

    $pageNumber = 1
    $pageSize = 100

    do {
        $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method $Method -Params $Params -Filter $Filter -PageNumber $pageNumber -PageSize $pageSize -TimeoutSec $TimeoutSec
        if ($responseError) {
            $errorMessage = !$responseError.code ? $responseError : "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
            Write-Host+ $errorMessage -ForegroundColor Red
            Write-Log -Message $errorMessage -EntryType "Error" -Action $Method -Status "Error"
            return
        }
        if (!$response) { break }
        $objects += $response
        $pagenumber += 1
    } until ($pagination.IsLastPage)

    if ($objects -and $Download) {
        foreach ($object in $objects) {
            $response = Download-TSObject -Method ($Method -replace "s$","") -InputObject $object
            if ($response.error) {
                $errorMessage = "Error $($response.error.code) ($($response.error.summary)): $($response.error.detail)"
                Write-Log -Message $errorMessage -EntryType "Error" -Action $Method -Status "Error"
                $object.SetAttribute("error", ($response | ConvertTo-Json -Compress))
            }
            else {
                $object.SetAttribute("outFile", $response.outFile)
            }
        }
    }

    return $objects

}

function global:Invoke-TSMethod {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Method,
        [Parameter(Mandatory=$false,Position=1)][string[]]$Params,
        [Parameter(Mandatory=$false)][int]$TimeoutSec = 0
    )

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method $Method -Params $Params -TimeoutSec $TimeoutSec
    if ($responseError) {
        $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
        Write-Host+ $errorMessage -ForegroundColor Red
        Write-Log -Message $errorMessage -EntryType "Error" -Action $Method -Status "Error"
        return
    }

    return $response

}

function global:Find-TSObject {

    param(
        [Parameter(Mandatory=$false,ParameterSetName="ById")]
        [Parameter(Mandatory=$false,ParameterSetName="ByName")]
        [Parameter(Mandatory=$false,ParameterSetName="ByContentUrl")]
        [Parameter(Mandatory=$false,ParameterSetName="ByOwnerId")]
        [Alias("Sites","Projects","Groups","Users","Workbooks","Views","Datasources","Favorites")]
        [object[]]
        $InputObject,

        [Parameter(Mandatory=$true,ParameterSetName="ById")]
        [Parameter(Mandatory=$true,ParameterSetName="ByName")]
        [Parameter(Mandatory=$true,ParameterSetName="ByContentUrl")]
        [Parameter(Mandatory=$false,ParameterSetName="ByOwnerId")]
        [ValidateSet("Site","Project","Group","User","Workbook","View","Datasource","Favorite")]
        [string]
        $Type,

        [Parameter(Mandatory=$true,ParameterSetName="ById")]
        [string]
        $Id,

        [Parameter(Mandatory=$true,ParameterSetName="ByName")]
        [string]
        $Name,

        [Parameter(Mandatory=$true,ParameterSetName="ByContentUrl")]
        [string]
        $ContentUrl,

        [Parameter(Mandatory=$false,ParameterSetName="ByOwnerId")]
        [string]
        $OwnerId,

        [Parameter(Mandatory=$false,ParameterSetName="ById")]
        [Parameter(Mandatory=$false,ParameterSetName="ByName")]
        [Parameter(Mandatory=$false,ParameterSetName="ByContentUrl")]
        [Parameter(Mandatory=$false,ParameterSetName="ByOwnerId")]
        [string]
        $Operator="eq"
    )

    $obj = "$($type.ToLower())s"
    
    if (!(Invoke-Expression "`$$obj")) {
        $InputObject = Invoke-Expression "Get-TS$($obj)"
        if (!$InputObject) {
            throw "Missing $Types object"
        }
    }
    
    if ($Id) {$where = "{`$_.id -$Operator `$Id}"}
    if ($Name) {
        switch ($Type) {
            "Favorite" {$where = "{`$_.label -$Operator `$Name}"}
            default {$where = "{`$_.name -$Operator `$Name}"}
        }
    }
    if ($ContentUrl) {$where = "{`$_.contentUrl -$Operator `$ContentUrl}"}
    if ($OwnerId) {$where = "{`$_.owner.id -$Operator `$OwnerId}"}
    
    $search = "`$InputObject | Where-Object $where"
    
    $result = Invoke-Expression $search

    return $result
}    

#endregion OBJECT
#region SITE

function global:Switch-TSSite {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][Alias("Site")][string]$ContentUrl = ""
    )

    # if (IsTableauCloud) { return }

    if ($ContentUrl -notin (Get-TSSites).contentUrl) {    
        $message = "Site `"$ContentUrl`" is not a valid contentURL for a site on $($global:tsRestApiConfig.Server)"
        Write-Host+ $message -ForegroundColor Red
        Write-Log -Message $message -EntryType "Error" -Action "SwitchSite" -Target $ContentUrl -Status "Error"
        return
    }

    if ($ContentUrl -eq $global:tsRestApiConfig.ContentUrl) {return}

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "SwitchSite" -Params @($ContentUrl)
    if ($responseError) {
        return
    }

    $global:tsRestApiConfig.Token = $response.token
    $global:tsRestApiConfig.SiteId = $response.site.id
    $global:tsRestApiConfig.ContentUrl = $response.site.contentUrl
    $global:tsRestApiConfig.UserId = $response.user.id 
    # $global:tsRestApiConfig.Headers = @{"Content-Type" = $global:tsRestApiConfig.ContentType; "X-Tableau-Auth" = $global:tsRestApiConfig.Token}

    $serverInfo = Get-TsServerInfo

    $global:tsRestApiConfig.RestApiVersioning = @{
        ApiVersion = $serverInfo.restApiVersion
        Headers = @{
            "Accept" = "*/*"
            "Content-Type" = "application/xml"
            "X-Tableau-Auth" = $global:tsRestApiConfig.Token
        }
        ApiUri = ""
    }
    $global:tsRestApiConfig.RestApiVersioning.ApiUri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)"
    $global:tsRestApiConfig.PerResourceVersioning = @{
        ApiVersion = "-"
        Headers = @{
            "Accept" = "*/*"
            "Content-Type" = "application/vnd.<ResourceString>+json"
            "X-Tableau-Auth" = $global:tsRestApiConfig.Token
        }
        ApiUri = ""
    }
    $global:tsRestApiConfig.PerResourceVersioning.ApiUri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.PerResourceVersioning.ApiVersion)"

    Update-TSRestApiMethods

    return
}

function global:Get-TSSites {

    [CmdletBinding()]
    param()

    if (IsTableauCloud) { return Get-TSSite }

    return Get-TSObjects -Method GetSites
}

function global:Get-TSSite {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method GetSite

}

function global:Get-TSCurrentSite {

    [CmdletBinding()]
    param()

    return (Get-TSCurrentSession).site

}

function global:Find-TSSite {
    param(
        [Parameter(Mandatory=$false)][object]$Site,
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$ContentUrl,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )
    if ([string]::IsNullOrEmpty($Id) -and [string]::IsNullOrEmpty($Name) -and [string]::IsNullOrEmpty($ContentUrl)) {
        Write-Host+ "ERROR: The search parameters `$Id, `$Name and `$ContentUrl are null." -ForegroundColor Red
        return
    }
    if (!$Site) { $Site = Get-TSSites }
    $params = @{Operator = $Operator}
    if ($Id) {$params += @{Id = $Id}}
    if ($Name) {$params += @{Name = $Name}}
    if ($ContentUrl) {$params += @{ContentUrl = $ContentUrl}}
    return Find-TSObject -Type "Site" -Sites $Sites @params
}

#endregion SITE
#region USERS

function global:Get-TSUsers+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers)
    )

    $usersPlus = @()
    $Users | ForEach-Object {
        $user = @{}
        $userMembers = $_ | Get-Member -MemberType Property
        foreach ($member in  $userMembers) {
            $user.($member.Name) = $_.($member.Name)
        }
        $user.membership = Get-TSUserMembership -User $_
        $usersPlus += $user
    }

    return $usersPlus
    
}

function global:Get-TSUsers {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method GetUsers
}

function global:Get-TSUser {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false,Position=0)][string]$Id = ((Get-TSCurrentUser).id)
    )

    return Get-TSObjects -Method GetUser -Params @($Id)
}

function global:Get-TSCurrentUser {

    [CmdletBinding()]
    param()

    return (Get-TSCurrentSession).user

}

function global:Find-TSUser {
    param(
        [Parameter(Mandatory=$false)][object]$Users,
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )
    if ([string]::IsNullOrEmpty($Id) -and [string]::IsNullOrEmpty($Name)) {
        Write-Host+ "ERROR: The search parameters `$Id and `$Name are null." -ForegroundColor Red
        return
    }
    if (!$Users) { $Users  = Get-TSUsers }
    $params = @{Operator = $Operator}
    if ($Id) {$params += @{Id = $Id}}
    if ($Name) {$params += @{Name = $Name}}
    return Find-TSObject -Type "User" -Users $Users @Params
}

function global:Get-TSUserMembership {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false,Position=0)][object]$User = (Get-TSCurrentUser)
    )

    return Get-TSObjects -Method GetUserMembership -Params @($User.Id)

}

function global:Add-TSUser {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Site,
        [Parameter(Mandatory=$true)][string]$Username,
        [Parameter(Mandatory=$false)][string]$FullName,
        [Parameter(Mandatory=$false)][string]$Email,
        [Parameter(Mandatory=$false)][string]$SiteRole
    )

    if ([string]::IsNullOrEmpty($FullName)) {
        $errorMessage = "$($Site.contentUrl)\$Username : FullName is missing or invalid."
        Write-Log -Message $errorMessage.Split(":")[1].Trim() -EntryType "Error" -Action "AddUser" -Target "$($Site.contentUrl)\$($tsSiteUser.name)" -Status "Error" 
        return
    }
    if ([string]::IsNullOrEmpty($Email)) {
        $errorMessage = "$($Site.contentUrl)\$Username : Email is missing or invalid."
        Write-Log -Message $errorMessage.Split(":")[1].Trim() -EntryType "Error" -Action "AddUser" -Target "$($Site.contentUrl)\$($tsSiteUser.name)" -Status "Error" 
        return
    }

    $SiteRole = $SiteRole -in $global:TSSiteRoles ? $SiteRole : "Unlicensed"

    # $response is a user object or an error object
    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "AddUser" -Params @($Username,$SiteRole)
    if ($responseError) {

        return
    }
    else {
        $tsSiteUser = $response # $response is a user object
        Write-Log -Action "AddUser" -Target "$($Site.contentUrl)\$($tsSiteUser.name)" -Message "$($tsSiteUser.name) | $($tsSiteUser.siteRole)" -Status "Success" -Force 
        
        # $response is an update object (NOT a user object) or an error object
        $response = Update-TSSiteUser -User $tsSiteUser -FullName $FullName -Email $Email -SiteRole $SiteRole
        if (!$response.error.code) {
            $response = Update-TSUserPassword -User $tsSiteUser -Password (New-RandomPassword -ExcludeSpecialCharacters)
        }
    }

    # $response is a user object, an update object or an error object
    return $response

}
Set-Alias -Name Add-TSUserToSite -Value Add-TSUser -Scope Global

function global:Update-TSUser {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$User,
        [Parameter(Mandatory=$false)][string]$FullName,
        [Parameter(Mandatory=$false)][string]$Email,
        [Parameter(Mandatory=$false)][string]$SiteRole
    )

    if ($FullName -eq $User.fullName -and $Email -eq $User.name -and $SiteRole -eq $User.siteRole) {return}

    $action = $SiteRole -eq "Unlicensed" ? "DisableUser" : "UpdateUser"

    $update = $null
    if (![string]::IsNullOrEmpty($FullName) -and $FullName -ne $User.fullname) {$update += "$($update ? " | " : $null)$($User.fullname ? "$($User.fullname) > " : $null)$($FullName)"}
    if (![string]::IsNullOrEmpty($Email) -and $Email -ne $User.name) {$update += "$($update ? " | " : $null)$($User.name ? "$($User.name) > " : $null)$($Email)"}
    if (![string]::IsNullOrEmpty($SiteRole) -and $SiteRole -ne $User.siteRole) {$update += "$($update ? " | " : $null)$($User.siteRole ? "$($User.siteRole) > " : $null)$($SiteRole)"}

    $FullName = $FullName ? $FullName : $User.fullName
    $Email = $Email ? $Email : $User.Name

    # apostrophes and xml don't mix, so replace both apostrophe characters with "&apos;""
    $FullName = $FullName.replace("'","&apos;").replace("’","&apos;")
    $Email = $Email.replace("'","&apos;").replace("’","&apos;")

    $SiteRole = $SiteRole -in $global:TSSiteRoles ? $SiteRole : $User.SiteRole
    
    # $response is an update object (NOT a user object) or an error object
    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "UpdateUser" -Params @($User.Id,$FullName,$Email,$SiteRole)
    if ($responseError) { 
        return
    }
    else {
        Write-Log -Action $action -Target "$($global:tsRestApiConfig.ContentUrl)\$($User.name)" -Message $update -Status "Success" -Force 
    }

    # $response is an update object or an error object
    return $response, $responseError

}
Set-Alias -Name Update-TSSiteUser -Value Update-TSUser -Scope Global

function global:Update-TSUserPassword {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$User,
        [Parameter(Mandatory=$true)][string]$Password
    )

    # $response is an update object (NOT a user object) or an error object
    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "UpdateUserPassword" -Params @($User.id,$Password)
    if ($responseError) { 
        return
    }
    else {
        Write-Log -Action "UpdateUserPassword" -Target "$($global:tsRestApiConfig.ContentUrl)\$($User.name)" -Status "Success" -Force 
    }

    # $response is an update object or an error object
    return $response

}

function global:Remove-TSUser {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Site,
        [Parameter(Mandatory=$true)][object]$User
    )

    $response, $pagination, $responseError = Invoke-TsRestApiMethod -Method "RemoveUser" -Params @($User.Id)
    if ($responseError) {
        # do nothing
    }
    else {
        Write-Log -Action "RemoveUser" -Target "$($global:tsRestApiConfig.ContentUrl)\$($User.name)" -Status "Success" -Force 
    }

    return $response, $responseError

} 
Set-Alias -Name Remove-TSUserFromSite -Value Remove-TSUser -Scope Global

#endregion USERS
#region GROUPS

function global:Get-TSGroups+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups)
    )

    $groupsPlus = @()
    $Groups | ForEach-Object {
        $group = @{}
        $groupMembers = $_ | Get-Member -MemberType Property
        foreach ($member in  $groupMembers) {
            $group.($member.Name) = $_.($member.Name)
        }
        $group.membership = Get-TSGroupMembership -Group $_
        $groupsPlus += $group
    }

    return $groupsPlus
    
}

function global:Get-TSGroups {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method GetGroups
}

function global:Find-TSGroup {
    param(
        [Parameter(Mandatory=$false)][object]$Groups,
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )
    if ([string]::IsNullOrEmpty($Id) -and [string]::IsNullOrEmpty($Name)) {
        Write-Host+ "ERROR: The search parameters `$Id and `$Name are null." -ForegroundColor Red
        return
    }
    if (!$Groups) { $Groups = Get-TSGroups }
    $params = @{Operator = $Operator}
    if ($Id) {$params += @{Id = $Id}}
    if ($Name) {$params += @{Name = $Name}}
    return Find-TSObject -Type "Group" -Groups $Groups @params
}    

function global:Get-TSGroupMembership {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Group
    )

    return Get-TSObjects -Method GetGroupMembership -Params @($Group.Id)

}

function global:Add-TSUserToGroup {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Group,
        [Parameter(Mandatory=$true)][object[]]$User
    )

    $User | ForEach-Object {
        $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "AddUserToGroup" -Params @($Group.Id,$_.Id)
        if ($responseError) {
            return
        }
        else {
            Write-Log -Action "AddUserToGroup" -Target "$($global:tsRestApiConfig.ContentUrl)\$($Group.name)\$($_.Name)" -Status "Success" -Force
        }

    }

    return

}

function global:Remove-TSUserFromGroup {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Group,
        [Parameter(Mandatory=$true)][object[]]$User
    )

    $User | ForEach-Object {
        $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "RemoveUserFromGroup" -Params @($Group.Id,$_.Id)
        if ($responseError) {
            return
        }
        else {
            Write-Log -Action "RemoveUserFromGroup" -Target "$($global:tsRestApiConfig.ContentUrl)\$($Group.name)\$($_.Name)" -Status "Success" -Force
        }
    }

    return
}   

#endregion GROUP
#region PROJECTS

function global:Get-TSProjects+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers),
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][object]$Projects,
        [Parameter(Mandatory=$false)][string]$Filter
    )

    if (!$Projects) {
        $params = @{}
        if ($Filter) { $params += @{ Filte = $Filter } }
        $Projects = Get-TSProjects @params
    }

    $projectPermissions = Get-TSProjectPermissions+ -Users $Users -Groups $Groups -Projects $Projects

    $projectsPlus = @()
    $Projects | ForEach-Object {
        $project = @{}
        $projectMembers = $_ | Get-Member -MemberType Property
        foreach ($member in  $projectMembers) {
            $project.($member.Name) = $_.($member.Name)
        }
        $project.owner = Find-TSUser -Users $Users -Id $_.owner.id
        $project.granteeCapabilities = $projectPermissions.$($_.id).granteeCapabilities
        $project.defaultPermissions = $projectPermissions.$($_.id).defaultPermissions
        $projectsPlus += $project
    }

    return $projectsPlus
}

function global:Get-TSProjects {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Filter
    )

    return Get-TSObjects -Method GetProjects -Filter $Filter

}

function global:Find-TSProject {
    
    param(
        [Parameter(Mandatory=$false)][object]$Projects,
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )

    if ([string]::IsNullOrEmpty($Id) -and [string]::IsNullOrEmpty($Name)) {
        return
    }
    if (!$Projects) { $Projects = Get-TSProjects+ }
    $params = @{Operator = $Operator}
    if ($Id) {$params += @{Id = $Id}}
    if ($Name) {$params += @{Name = $Name}}
    return Find-TSObject -Type "Project" -Projects $Projects @params

}

function global:Get-TSProjectPermissions+ {

    param(
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+),
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers)
    )

    if (!$Projects) {throw "Workbooks is empty"}
    if (!$Groups) {throw "Groups is empty"}
    if (!$Users) {throw "Users is empty"}

    $projectPermissions = Get-TSProjectPermissions -Project $Projects
    $projectPermissionsCount = ($projectPermissions.keys | ForEach-Object {$projectPermissions.$_.granteeCapabilities.count} | Measure-Object -Sum).Sum 

    $projectDefaultPermissions = @{}
    foreach ($permissionType in @("Workbooks","Datasources")) {   
        
        $projectDefaultPermissions.$permissionType = Get-TSProjectDefaultPermissions+ -Project $Projects -Type $permissionType
        $projectPermissionsCount += ($projectDefaultPermissions.$permissionType.keys | ForEach-Object {$projectDefaultPermissions.$permissionType.$_.granteeCapabilities.count} | Measure-Object -Sum).Sum
        
    }

    $projectPermissionsPlus = @{}
    foreach ($projectKey in $Projects.id) {

        $perm = @{
            project = Find-TSProject -id $projectKey -Projects $Projects
            granteeCapabilities = @()
            defaultPermissions = @{}
        }
        foreach ($permissionType in @("Workbooks","Datasources")) {
            $perm.defaultPermissions.$permissionType = $projectDefaultPermissions.$permissionType.$projectKey
        }

        foreach ($granteeCapability in $projectPermissions.$projectKey.granteeCapabilities) { 
            $granteeCapabilityPlus = @{capabilities = $granteeCapability.capabilities}
            if ($granteeCapability.user) {
                $granteeCapabilityPlus.user = Find-TSUser -Users $users -Id $granteeCapability.user.id
            }
            elseif ($granteeCapability.group) {
                $granteeCapabilityPlus.group = Find-TSGroup -Groups $groups -Id $granteeCapability.group.id
            }
            $perm.granteeCapabilities += $granteeCapabilityPlus
        }

        $projectPermissionsPlus += @{$projectKey = $perm}
    }

    return $projectPermissionsPlus
}

function global:Get-TSProjectPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object[]]$Projects
    )

    $projectPermissions = @{}
    foreach ($project in $Projects) {
        $projectPermissions += @{$project.id = Get-TSObjects -Method GetProjectPermissions -Params @($Project.Id,$Type)}
    }
    
    return $projectPermissions

}

function global:Add-TSProjectPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Project,
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet(
            "Read:Allow","Read:Deny",
            "Write:Allow","Write:Deny",
            "ProjectLeader:Allow","ProjectLeader:Deny",
            "InheritedProjectLeader:Allow","InheritedProjectLeader:Deny"
        )]
        [string[]]$Capabilities 
    )

    if (!($Group -or $User) -or ($Group -and $User)) {
        throw "Must specify either Group or User"
    }

    $grantee = $Group ?? $User
    $granteeType = $Group ? "group" : "user"
    $capabilityXML = "<$granteeType id='$($grantee.id)'/>"
    
    $capabilityXML += "<capabilities>"
    foreach ($capability in $Capabilities) {
        $name,$mode = $capability -split ":"
        $capabilityXML += "<capability name='$name' mode='$mode'/>"
    }
    $capabilityXML += "</capabilities>"

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method AddProjectPermissions -Params @($Project.id,$capabilityXML)
    # if ($responseError) { #}.code -eq "401002") {
    #     $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
    #     Write-Host+ $errorMessage -ForegroundColor Red
    #     Write-Log -Message $errorMessage -EntryType "Error" -Action "AddProjectPermissions" -Status "Error"
    #     # return
    # }
    
    return $response,$responseError
}

function global:Remove-TSProjectPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Project,
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet(
            "Read:Allow","Read:Deny",
            "Write:Allow","Write:Deny",
            "ProjectLeader:Allow","ProjectLeader:Deny",
            "InheritedProjectLeader:Allow","InheritedProjectLeader:Deny"
        )]
        [string[]]$Capabilities 
    )

    if (!($Group -or $User) -or ($Group -and $User)) {
        throw "Must specify either Group or User"
    }

    $grantee = $Group ?? $User
    $granteeType = $Group ? "groups" : "users"

    foreach ($capability in $Capabilities) {
        $capabilityName,$capabilityMode = $capability.split(":")
        $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "RemoveProjectPermissions" -Params @($Project.id,$granteeType,$grantee.Id,$capabilityName,$capabilityMode)
        # if ($responseError) { #}.code -eq "401002") {
        #     $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
        #     Write-Host+ $errorMessage -ForegroundColor Red
        #     Write-Log -Message $errorMessage -EntryType "Error" -Action "RemoveProjectPermissions" -Status "Error"
        #     # return
        # }
    }
    
    return $response,$responseError
}

function global:Get-TSProjectDefaultPermissions+ {

    param(
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+),
        [Parameter(Mandatory=$true)][string]$Type,
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers)
    )

    if (!$Projects) {throw "Projects is empty"}
    if (!$Groups) {throw "Groups is empty"}
    if (!$Users) {throw "Users is empty"}
    if (!$Type) {throw "Type is empty"}

    $projectDefaultPermissions = Get-TSProjectDefaultPermissions -Projects $Projects -Type $Type

    $projectDefaultPermissionsPlus = @{}
    foreach ($projectKey in $Projects.id) {
        $perm = @{
            project = Find-TSProject -id $projectKey -Projects $Projects
            granteeCapabilities = @()
            defaultPermissions = $true
            permissionType = $Type
        }
        foreach ($granteeCapability in $projectDefaultPermissions.$projectKey.GranteeCapabilities) { 
            $granteeCapabilityPlus = @{capabilities = $granteeCapability.capabilities}
            if ($granteeCapability.user) {
                $granteeCapabilityPlus.user = Find-TSUser -Users $users -Id $granteeCapability.user.id
            }
            elseif ($granteeCapability.group) {
                $granteeCapabilityPlus.group = Find-TSGroup -Groups $groups -Id $granteeCapability.group.id
            }
            $perm.granteeCapabilities += $granteeCapabilityPlus
        }
        $projectDefaultPermissionsPlus += @{$projectKey = $perm}
        
    }

    return $projectDefaultPermissionsPlus
}

function global:Get-TSProjectDefaultPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object[]]$Projects,
        [Parameter(Mandatory=$true)][ValidateSet("Workbooks","Datasources","Metrics","Flows")][string]$Type
    )

    $projectDefaultPermissions = @{}
    foreach ($project in $Projects) {
        $projectDefaultPermissions += @{$project.id = Get-TSObjects -Method GetProjectDefaultPermissions -Params @($Project.Id,$Type)}
    }
    
    return $projectDefaultPermissions
}

function global:Add-TSProjectDefaultPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Project,
        [Parameter(Mandatory=$true)][ValidateSet("Workbooks","Datasources","Flows","Metrics")][string]$Type, # "DataRoles"
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        [Parameter(Mandatory=$false)][string[]]$Capabilities 
    )

    switch ($Type) {
        "Workbooks" {
            $Capabilities | Foreach-Object {
                if ($_ -notin $workbookPermissions) {
                    throw "$($_) is not a valid capability"
                }
            }
        }
        "Views" {
            $Capabilities | Foreach-Object {
                if ($_ -notin $viewPermissions) {
                    throw "$($_) is not a valid capability"
                }
            }
        }
        "Datasources" {
            $Capabilities | Foreach-Object {
                if ($_ -notin $dataSourcePermissions) {
                    throw "$($_) is not a valid capability"
                }
            }
        }
        "Flows" {
            $Capabilities | Foreach-Object {
                if ($_ -notin $flowPermissions) {
                    throw "$($_) is not a valid capability"
                }
            }
        }
    }

    
    if (!($Group -or $User) -or ($Group -and $User)) {
        throw "Must specify either Group or User"
    }

    $grantee = $Group ?? $User
    $granteeType = $Group ? "group" : "user"
    $capabilityXML = "<$granteeType id='$($grantee.id)'/>"
    
    $capabilityXML += "<capabilities>"
    foreach ($capability in $Capabilities) {
        $name,$mode = $capability -split ":"
        $capabilityXML += "<capability name='$name' mode='$mode'/>"
    }
    $capabilityXML += "</capabilities>"

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "AddProjectDefaultPermissions" -Params @($Project.id,$Type,$capabilityXML)
    # if ($responseError) { #}.code -eq "401002") {
    #     $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
    #     Write-Host+ $errorMessage -ForegroundColor Red
    #     Write-Log -Message $errorMessage -EntryType "Error" -Action "AddProjectDefaultPermissions" -Status "Error"
    #     # return
    # }
    
    return $response,$responseError
}

function global:Remove-TSProjectDefaultPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Project,
        [Parameter(Mandatory=$true)][ValidateSet("Workbooks","Datasources")][string]$Type,
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        [Parameter(Mandatory=$false)][string[]]$Capabilities 
    )

    switch ($Type) {
        "Workbooks" {
            $Capabilities | Foreach-Object {
                if ($_ -notin $workbookPermissions) {
                    throw "$($_) is not a valid capability"
                }
            }
        }
        "Views" {
            $Capabilities | Foreach-Object {
                if ($_ -notin $viewPermissions) {
                    throw "$($_) is not a valid capability"
                }
            }
        }            
        "Datasources" {
            $Capabilities | Foreach-Object {
                if ($_ -notin $dataSourcePermissions) {
                    throw "$($_) is not a valid capability"
                }
            }
        }
        "Flows" {
            $Capabilities | Foreach-Object {
                if ($_ -notin $flowPermissions) {
                    throw "$($_) is not a valid capability"
                }
            }
        }
    }

    
    if (!($Group -or $User) -or ($Group -and $User)) {
        throw "Must specify either Group or User"
    }

    $grantee = $Group ?? $User
    $granteeType = $Group ? "groups" : "users"

    foreach ($capability in $Capabilities) {
        $capabilityName,$capabilityMode = $capability.split(":")
        $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "RemoveProjectDefaultPermissions" -Params @($Project.id,$Type,$granteeType,$grantee.Id,$capabilityName,$capabilityMode)
        # if ($responseError) { #}.code -eq "401002") {
        #     $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
        #     Write-Host+ $errorMessage -ForegroundColor Red
        #     Write-Log -Message $errorMessage -EntryType "Error" -Action "RemoveProjectDefaultPermissions" -Status "Error"
        #     # return
        # }
    }
    
    return $response,$responseError
}

#endregion PROJECTS
#region WORKBOOKS

function global:Get-TSWorkbooks+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers),
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+),
        [Parameter(Mandatory=$false)][string]$Filter,
        [Parameter(Mandatory=$false)][switch]$Download
    )

    $workbooks = (Get-TSWorkbooks -Filter $Filter -Download:$Download.IsPresent)
    if (!$workbooks) { return }

    $workbookPermissions = Get-TSWorkbookPermissions+ -Users $Users -Groups $Groups -Workbooks $workbooks

    # $col1 = @{ label = "Project"; value = $null; width = 50 }
    # $col2 = @{ label = "Workbook"; value = $null; width = 50 }
    # Write-Host+ -NoTimestamp -NoSeparator $col1.label,$emptyString.PadLeft($col1.width-$col1.label.Length," "),$col2.label,$emptyString.PadLeft($col2.width-$col2.label.Length," ")
    # Write-Host+ -NoTrace -NoTimestamp -NoSeparator $emptyString.PadLeft($col1.label.Length,"-"),$emptyString.PadLeft($col1.width-$col1.label.Length," "),$emptyString.PadLeft($col2.label.Length,"-"),$emptyString.PadLeft($col2.width-$col2.label.Length," ")

    $workbooksPlus = @()
    $workbooks | ForEach-Object {

        # $col1.value = $_.project ? $_.project.Name : "Personal Space ($((Find-TSUser -Users $Users -Id $_.owner.id).fullName))"
        # $col1.value = $col1.value.substring(0,($col1.value.length -gt $col1.width ? $col1.width-1 : $col1.value.length))
        # $col1.value = $col1.value.PadRight($col1.width," ")
        # $col2.value = $_.name
        # $col2.value = $col2.value.substring(0,($col2.value.length -gt $col2.width ? $col2.width-1 : $col2.value.length))
        # $col2.value = $col2.value.PadRight($col2.width," ")
        # Write-Host+ -NoTrace -NoTimestamp $col1.value,$col2.value

        $workbook = @{}
        $workbookMembers = $_ | Get-Member -MemberType Property
        foreach ($member in  $workbookMembers) {
            $workbook.($member.Name) = $_.($member.Name)
        }
        $workbook.objectType = "workbook"
        $workbook.owner = Find-TSUser -Users $Users -Id $_.owner.id
        $workbook.project = Find-TSProject -Projects $Projects -Id $_.project.id
        $workbook.granteeCapabilities = $workbookPermissions.$($_.id).granteeCapabilities
        $workbook.revisions = Get-TSWorkbookRevisions -Workbook $_
        $workbook.connections = Get-TSWorkbookConnections -Id $_.id
        $workbooksPlus += $workbook

    }

    return $workbooksPlus
}

function global:Get-TSWorkbooks {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Filter,
        [switch]$Download
    )

    return Get-TSObjects -Method GetWorkbooks -Filter $Filter -Download:$Download.IsPresent

}

function global:Get-TSWorkbook+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Id,
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers),
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+),
        [Parameter(Mandatory=$false)][string]$Filter,
        [Parameter(Mandatory=$false)][switch]$Download
    )

    $workbook = Get-TSWorkbook -Id $Id -Filter $Filter -Download:$Download.IsPresent
    $workbookPermissions = Get-TSWorkbookPermissions+ -Users $Users -Groups $Groups -Workbooks $workbook

    $workbookPlus = @{}
    $workbookMembers = $workbook | Get-Member -MemberType Property
    foreach ($member in  $workbookMembers) {
        $workbookPlus.($member.Name) = $workbook.($member.Name)
    }
    $workbookPlus.objectType = "workbook"
    $workbookPlus.owner = Find-TSUser -Users $Users -Id $workbook.owner.id
    $workbookPlus.project = Find-TSProject -Projects $Projects -Id $workbook.project.id
    $workbookPlus.granteeCapabilities = $WorkbookPermissions.$Id.granteeCapabilities
    $workbookPlus.revisions = Get-TSWorkbookRevisions -Workbook $workbook
    $workbookPlus.connections = Get-TSWorkbookConnections -Id $workbook.id

    return $workbookPlus
}

function global:Get-TSWorkbook {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [switch]$Download
    )

    return Get-TSObjects -Method GetWorkbook -Params @($Id) -Download:$Download.IsPresent

}

function global:Update-TSWorkbook {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Workbook,
        [Parameter(Mandatory=$false)][object]$Project = $Workbook.Project,
        [Parameter(Mandatory=$false)][object]$Owner = $Workbook.Owner
    )

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method UpdateWorkbook -Params @($Workbook.Id, $Workbook.Name, $Project.Id, $Owner.Id) 

    return $response, $responseError

}

function global:Get-TSWorkbookConnections {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id
    )

    return Get-TSObjects -Method GetWorkbookConnections -Params @($Id)
}

function global:Find-TSWorkbook {
    param(
        [Parameter(Mandatory=$false)][object]$Workbooks,
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][object]$Owner,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )
    if ([string]::IsNullOrEmpty($Id) -and [string]::IsNullOrEmpty($Name) -and [string]::IsNullOrEmpty($Owner)) {
        Write-Host+ "ERROR: The search parameters `$Id, `$Name and `$Owner are null." -ForegroundColor Red
        return
    }
    if (!$Workbooks) { $Workbooks  = Get-TSWorkbooks }
    $params = @{Operator = $Operator}
    if ($Id) {$params += @{Id = $Id}}
    if ($Name) {$params += @{Name = $Name}}
    if ($Owner) {$params += @{OwnerId = $Owner.id}}
    return Find-TSObject -Type "Workbook" -Workbooks $Workbooks @Params
}

function global:Get-TSWorkbookPermissions+ {

    param(
        [Parameter(Mandatory=$false)][object]$Workbooks = (Get-TSWorkbooks+),
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers)
    )

    if (!$Workbooks) {throw "Workbooks is empty"}
    if (!$Groups) {throw "Groups is empty"}
    if (!$Users) {throw "Users is empty"}
    
    $workbookPermissions = @{}
    foreach ($workbook in $workbooks) {
        $permissions = Get-TSWorkbookPermissions -Workbook $Workbook
        foreach ($defaultPermission in $permissions) {
            $perm = @{workbook = $workbook; granteeCapabilities = @()}
            foreach ($granteeCapability in $defaultPermission.GranteeCapabilities) { 
                $granteeCapabilityPlus = @{capabilities = $granteeCapability.capabilities}
                if ($granteeCapability.user) {
                    $granteeCapabilityPlus.user = Find-TSUser -Users $users -Id $granteeCapability.user.id
                }
                elseif ($granteeCapability.group) {
                    $granteeCapabilityPlus.group = Find-TSGroup -Groups $groups -Id $granteeCapability.group.id
                }
                $perm.granteeCapabilities += $granteeCapabilityPlus
            }
            $workbookPermissions += @{$workbook.id = $perm}
        }
    }

    return $workbookPermissions
}

function global:Get-TSWorkbookPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Workbook
    )

    if ($Workbook.location.type -eq "PersonalSpace") {
        $responseError = "Method 'GetWorkbookPermissions' is not authorized for workbooks in a personal space."
        Write-Log -EntryType "Error" -Action "GetWorkbookPermissions" -Target "workbooks\$($Workbook.id)" -Status "Forbidden" -Message $responseError 
        return
    }
    
    return Get-TSObjects -Method "GetWorkbookPermissions" -Params @($Workbook.Id)

}

function global:Add-TSWorkbookPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Workbook,
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        [Parameter(Mandatory=$false)][string[]]$Capabilities 
    )

    if ($Workbook.location.type -eq "PersonalSpace") {
        $responseError = "Method 'AddWorkbookPermissions' is not authorized for workbooks in a personal space."
        Write-Log -EntryType "Error" -Action "AddWorkbookPermissions" -Target "workbooks\$($Workbook.id)" -Status "Forbidden" -Message $responseError 
        return
    }

    if (!($Group -or $User) -or ($Group -and $User)) {
        throw "Must specify either Group or User"
    }

    $Capabilities | Foreach-Object {
        if ($_ -notin $WorkbookPermissions) {
            throw "$($_) is not a valid capability"
        }
    }        

    $grantee = $Group ?? $User
    $granteeType = $Group ? "group" : "user"
    $capabilityXML = "<$granteeType id='$($grantee.id)'/>"
    
    $capabilityXML += "<capabilities>"
    foreach ($capability in $Capabilities) {
        $name,$mode = $capability -split ":"
        $capabilityXML += "<capability name='$name' mode='$mode'/>"
    }
    $capabilityXML += "</capabilities>"

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "AddWorkBookPermissions" -Params @($Workbook.id,$capabilityXML)
    # if ($responseError) { #}.code -eq "401002") {
    #     $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
    #     Write-Host+ $errorMessage -ForegroundColor Red
    #     Write-Log -Message $errorMessage -EntryType "Error" -Action "AddWorkBookPermissions" -Status "Error"
    #     # return
    # }
    
    return $response,$responseError
}

function global:Get-TSWorkbookRevisions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Workbook,
        [Parameter(Mandatory=$false)][string]$Revision,
        [switch]$Download
    )

    $workbookRevisions = Get-TSObjects -Method GetWorkbookRevisions -Params @($Workbook.Id)
    if ($Revision) { $workbookRevisions = $workbookRevisions | Where-Object {$_.revisionNumber -eq $Revision} }
    
    if ($workbookRevisions -and $Download) {
        foreach ($workbookRevision in $workbookRevisions) {
            $response = Download-TSObject -Method GetWorkbookRevision -InputObject $Workbook -Params @($Workbook.Id, $workbookRevision.revisionNumber)
            if ($response.error) {
                $errorMessage = "Error $($response.error.code) ($($response.error.summary)): $($response.error.detail)"
                Write-Log -Message $errorMessage -EntryType "Error" -Action $Method -Status "Error"
                $workbookRevision.SetAttribute("error", ($response | ConvertTo-Json -Compress))
            }
            else {
                $workbookRevision.SetAttribute("outFile", $response.outFile)
            }
        }
    }

    return $workbookRevisions

}

function global:Get-TSWorkbookRevision {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Workbook,
        [Parameter(Mandatory=$true)][string]$Revision,
        [switch]$Download
    )

    return Get-TSWorkbookRevisions -Workbook $Workbook -Revision $Revision -Download:$Download.IsPresent

}

#endregion WORKBOOKS
#region VIEWS

function global:Get-TSViews+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers),
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+),
        [Parameter(Mandatory=$false)][object]$Workbooks = (Get-TSWorkbooks+),
        [Parameter(Mandatory=$false)][object]$Views = (Get-TSViews)
    )

    if (!$Views) {
        return
    }

    $viewPermissions = Get-TSViewPermissions+ -Users $Users -Groups $Groups -Views $Views

    $viewsPlus = @()
    $Views | ForEach-Object {
        $view = @{}
        $viewMembers = $_ | Get-Member -MemberType Property
        foreach ($member in  $viewMembers) {
            $view.($member.Name) = $_.($member.Name)
        }
        $view.owner = Find-TSUser -Users $Users -Id $_.owner.id
        $view.project = Find-TSProject -Projects $Projects -Id $_.project.id
        $view.workbook = Find-TSWorkbook -Workbooks $Workbooks -Id $_.workbook.id
        $view.granteeCapabilities = $viewPermissions.$($_.id).granteeCapabilities
        $viewsPlus += $view
    }

    return $viewsPlus
}

function global:Get-TSViews {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Workbook
    )

    if ($Workbook) {
        return Get-TSObjects -Method "GetViewsForWorkbook" -Params @($Workbook.id)
    }
    else {
        return Get-TSObjects -Method "GetViewsForSite"
    }
    
    return
}

function global:Find-TSView {
    param(
        [Parameter(Mandatory=$false)][object]$Views,
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][object]$Owner,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )
    if ([string]::IsNullOrEmpty($Id) -and [string]::IsNullOrEmpty($Name) -and [string]::IsNullOrEmpty($Owner)) {
        Write-Host+ "ERROR: The search parameters `$Id, `$Name and `$Owner are null." -ForegroundColor Red
        return
    }
    if (!$Views) { $Views = Get-TSViews }
    $params = @{Operator = $Operator}
    if ($Id) {$params += @{Id = $Id}}
    if ($Name) {$params += @{Name = $Name}}
    if ($Owner) {$params += @{OwnerId = $Owner.id}}
    return Find-TSObject -Type "View" -Views $Views @Params
}    

function global:Get-TSViewPermissions+ {

    param(
        [Parameter(Mandatory=$false)][object]$Views = (Get-TSViews+),
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers)
    )

    if (!$Views) {throw "Views is empty"}
    if (!$Groups) {throw "Groups is empty"}
    if (!$Users) {throw "Users is empty"}
    
    $viewPermissions = @{}
    foreach ($view in $views) {
        $permissions = Get-TSViewPermissions -View $View
        foreach ($defaultPermission in $permissions) {
            $perm = @{view = $view; granteeCapabilities = @()}
            foreach ($granteeCapability in $defaultPermission.GranteeCapabilities) { 
                $granteeCapabilityPlus = @{capabilities = $granteeCapability.capabilities}
                if ($granteeCapability.user) {
                    $granteeCapabilityPlus.user = Find-TSUser -Users $users -Id $granteeCapability.user.id
                }
                elseif ($granteeCapability.group) {
                    $granteeCapabilityPlus.group = Find-TSGroup -Groups $groups -Id $granteeCapability.group.id
                }
                $perm.granteeCapabilities += $granteeCapabilityPlus
            }
            $viewPermissions += @{$view.id = $perm}
        }
    }

    return $viewPermissions
}

function global:Get-TSViewPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$View
    )

    if ($View.location.type -eq "PersonalSpace") {
        $responseError = "Method 'GetViewPermissions' is not authorized for views in a personal space."
        Write-Log -EntryType "Error" -Action "GetViewPermissions" -Target "views\$($View.id)" -Status "Forbidden" -Message $responseError 
        return
    }

    return Get-TSObjects -Method "GetViewPermissions" -Params @($View.Id)
}

function global:Add-TSViewPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$View,
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        [Parameter(Mandatory=$false)][string[]]$Capabilities 
    )

    if ($View.location.type -eq "PersonalSpace") {
        $responseError = "Method 'AddViewPermissions' is not authorized for views in a personal space."
        Write-Log -EntryType "Error" -Action "AddViewPermissions" -Target "views\$($View.id)" -Status "Forbidden" -Message $responseError 
        return
    }

    if (!($Group -or $User) -or ($Group -and $User)) {
        throw "Must specify either Group or User"
    }

    $Capabilities | Foreach-Object {
        if ($_ -notin $ViewPermissions) {
            throw "$($_) is not a valid capability"
        }
    }  

    $grantee = $Group ?? $User
    $granteeType = $Group ? "group" : "user"
    $capabilityXML = "<$granteeType id='$($grantee.id)'/>"
    
    $capabilityXML += "<capabilities>"
    foreach ($capability in $Capabilities) {
        $name,$mode = $capability -split ":"
        $capabilityXML += "<capability name='$name' mode='$mode'/>"
    }
    $capabilityXML += "</capabilities>"

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "AddViewPermissions" -Params @($View.id,$capabilityXML)
    # if ($responseError) { #}.code -eq "401002") {
    #     $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
    #     Write-Host+ $errorMessage -ForegroundColor Red
    #     Write-Log -Message $errorMessage -EntryType "Error" -Action "AddViewPermissions" -Status "Error"
    #     # return
    # }
    
    return $response,$responseError
}

#endregion VIEWS
#region DATASOURCES

function global:Get-TSDatasources+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers),
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+),
        [Parameter(Mandatory=$false)][string]$Filter,
        [Parameter(Mandatory=$false)][switch]$Download
    )

    $datasources = Get-TSDatasources -Filter $Filter -Download:$Download.IsPresent
    if (!$datasources) { return }
    
    $datasourcePermissions = Get-TSDatasourcePermissions+ -Users $Users -Groups $Groups -Datasource $datasources

    $datasourcesPlus = @()
    $datasources | ForEach-Object {
        $datasource = @{}
        $datasourceMembers = $_ | Get-Member -MemberType Property
        foreach ($member in  $datasourceMembers) {
            $datasource.($member.Name) = $_.($member.Name)
        }
        $datasource.owner = Find-TSUser -Users $Users -Id $_.owner.id
        $datasource.project = Find-TSProject -Projects $Projects -Id $_.project.id
        $datasource.granteeCapabilities = $datasourcePermissions.$($_.id).granteeCapabilities
        $datasource.revisions = Get-TSDataSourceRevisions -Datasource $_
        $datasource.connections = Get-TSDataSourceConnections -Id $_.id
        $datasourcesPlus += $datasource
    }

    return $datasourcesPlus
}

function global:Get-TSDataSources {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Filter,
        [switch]$Download
    )

    return Get-TSObjects -Method GetDatasources -Filter $Filter -Download:$Download.IsPresent

}

function global:Get-TSDataSource {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [switch]$Download
    )

    return Get-TSObjects -Method GetDataSource -Params @($Id) -Download:$Download.IsPresent
}

function global:Update-TSDataSource {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$DataSource,
        [Parameter(Mandatory=$false)][object]$Project = $DataSource.Project,
        [Parameter(Mandatory=$false)][object]$Owner = $DataSource.Owner
    )

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method UpdateDataSource -Params @($DataSource.Id, $DataSource.Name, $Project.Id, $Owner.Id) 

    return $response, $responseError

}

function global:Get-TSDatasourceRevisions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Datasource,
        [Parameter(Mandatory=$false)][string]$Revision,
        [switch]$Download
    )

    $datasourceRevisions = Get-TSObjects -Method GetDatasourceRevisions -Params @($Datasource.Id)
    if ($Revision) { $datasourceRevisions = $datasourceRevisions | Where-Object {$_.revisionNumber -eq $Revision} }
    
    if ($datasourceRevisions -and $Download) {
        foreach ($datasourceRevision in $datasourceRevisions) {
            $response = Download-TSObject -Method GetDatasourceRevision -InputObject $Datasource -Params @($Datasource.Id, $datasourceRevision.revisionNumber)
            if ($response.error) {
                $errorMessage = "Error $($response.error.code) ($($response.error.summary)): $($response.error.detail)"
                Write-Log -Message $errorMessage -EntryType "Error" -Action $Method -Status "Error"
                $datasourceRevision.SetAttribute("error", ($response | ConvertTo-Json -Compress))
            }
            else {
                $datasourceRevision.SetAttribute("outFile", $response.outFile)
            }
        }
    }

    return $datasourceRevisions

}

function global:Get-TSDatasourceRevision {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Datasource,
        [Parameter(Mandatory=$true)][string]$Revision,
        [switch]$Download
    )

    return Get-TSDatasourceRevisions -Datasource $Datasource -Revision $Revision -Download:$Download.IsPresent

}

function global:Get-TSDataSourceConnections {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id
    )

    return Get-TSObjects -Method GetDataSourceConnections -Params @($Id)
}

function global:Find-TSDatasource {
    param(
        [Parameter(Mandatory=$false)][object]$Datasources,
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][object]$Owner,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )
    if ([string]::IsNullOrEmpty($Id) -and [string]::IsNullOrEmpty($Name) -and [string]::IsNullOrEmpty($Owner)) {
        Write-Host+ "ERROR: The search parameters `$Id, `$Name and `$Owner are null." -ForegroundColor Red
        return
    }
    if (!$Datasources) { $Datasources = Get-TSDatasources }
    $params = @{Operator = $Operator}
    if ($Id) {$params += @{Id = $Id}}
    if ($Name) {$params += @{Name = $Name}}
    if ($Owner) {$params += @{OwnerId = $Owner.id}}
    return Find-TSObject -Type "Datasource" -Datasources $Datasources @Params
}

function global:Get-TSDatasourcePermissions+ {

    param(
        [Parameter(Mandatory=$false)][object]$Datasources = (Get-TSDatasources+),
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers)
    )

    if (!$Datasources) {throw "Datasources is empty"}
    if (!$Groups) {throw "Groups is empty"}
    if (!$Users) {throw "Users is empty"}
    
    $datasourcePermissions = @{}
    foreach ($datasource in $datasources) {
        $permissions = Get-TSDatasourcePermissions -Datasource $Datasource
        foreach ($defaultPermission in $permissions) {
            $perm = @{datasource = $datasource; granteeCapabilities = @()}
            foreach ($granteeCapability in $defaultPermission.GranteeCapabilities) { 
                $granteeCapabilityPlus = @{capabilities = $granteeCapability.capabilities}
                if ($granteeCapability.user) {
                    $granteeCapabilityPlus.user = Find-TSUser -Users $users -Id $granteeCapability.user.id
                }
                elseif ($granteeCapability.group) {
                    $granteeCapabilityPlus.group = Find-TSGroup -Groups $groups -Id $granteeCapability.group.id
                }
                $perm.granteeCapabilities += $granteeCapabilityPlus
            }
            $datasourcePermissions += @{$datasource.id = $perm}
        }
    }

    return $datasourcePermissions
}

function global:Get-TSDatasourcePermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Datasource
    )

    return Get-TSObjects -Method GetDatasourcePermissions -Params @($Datasource.Id)
}

function global:Add-TSDataSourcePermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$DataSource,
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        [Parameter(Mandatory=$false)][string[]]$Capabilities 
    )

    if (!($Group -or $User) -or ($Group -and $User)) {
        throw "Must specify either Group or User"
    }

    
    $Capabilities | Foreach-Object {
        if ($_ -notin $DataSourcePermissions) {
            throw "$($_) is not a valid capability"
        }
    }  

    $grantee = $Group ?? $User
    $granteeType = $Group ? "group" : "user"
    $capabilityXML = "<$granteeType id='$($grantee.id)'/>"
    
    $capabilityXML += "<capabilities>"
    foreach ($capability in $Capabilities) {
        $name,$mode = $capability -split ":"
        $capabilityXML += "<capability name='$name' mode='$mode'/>"
    }
    $capabilityXML += "</capabilities>"

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "AddDataSourcePermissions" -Params @($DataSource.id,$capabilityXML)
    # if ($responseError) { #}.code -eq "401002") {
    #     $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
    #     Write-Host+ $errorMessage -ForegroundColor Red
    #     Write-Log -Message $errorMessage -EntryType "Error" -Action "AddDataSourcePermissions" -Status "Error"
    #     # return
    # }
    
    return $response,$responseError
}

#endregion DATASOURCES
#region FLOWS

function global:Get-TSFlows+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers),
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+),
        [Parameter(Mandatory=$false)][string]$Filter,
        [Parameter(Mandatory=$false)][switch]$Download
    )

    $flows = Get-TSFlows -Filter $Filter -Download:$Download.IsPresent
    if (!$flows) { return }

    $flowPermissions = Get-TSFlowPermissions+ -Users $Users -Groups $Groups -Flow $Flows

    $flowsPlus = @()
    $flows | ForEach-Object {
        $flow = @{}
        $flowMembers = $_ | Get-Member -MemberType Property
        foreach ($member in  $flowMembers) {
            $flow.($member.Name) = $_.($member.Name)
        }
        $flow.owner = Find-TSUser -Users $Users -Id $_.owner.id
        $flow.project = Find-TSProject -Projects $Projects -Id $_.project.id
        $flow.granteeCapabilities = $flowPermissions.$($_.id).granteeCapabilities
        $flowsPlus += $flow
    }

    return $flowsPlus
}

function global:Get-TSFlows {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Filter,
        [switch]$Download
    )

    $flows = @()
    foreach ($flow in Get-TSObjects -Method GetFlows -Filter $Filter) {
        $flows += Get-TSFlow -Id $flow.Id -Download:$Download.IsPresent
    }

    return $flows

}

function global:Get-TSFlow {

    [CmdletBinding()]
    param(        
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [switch]$Download
    )

    $flow = Get-TSObjects -Method GetFlow -Params @($Id)
    if (!$flow) { return }

    # special processing for downloading flows
    # the tsrestapi doesn't always successfully download flows (.tfl and .tflx)
    # occasionally, the tsrestapi returns "Page Not Found" with no content-disposition header
    # repeating the download 2-3 times has, thus far, succeeded:  thus the code below
    # this has to be a tsrestapi or tableau server bug - confirmed in postman
    # note: this has NEVER happened with workbooks or datasources

    if ($Download) { 
        $downloadAttemptsMax = 3
        $downloadAttempts = 0
        do {
            $flow = Get-TSObjects -Method GetFlow -Params @($flow.Id) -Download
            $downloadAttempts++
        }
        while ($flow.error -and $downloadAttempts -lt $downloadAttemptsMax)
        if ($flow.error -and $downloadAttempts -ge $downloadAttemptsMax) {
            Write-Host+ -NoTrace "Error: Max download attempts exceeded" -ForegroundColor Red
        }
    }

    return $flow

}

function global:Update-TSFlow {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Flow,
        [Parameter(Mandatory=$false)][object]$Project = $Flow.Project,
        [Parameter(Mandatory=$false)][object]$Owner = $Flow.Owner
    )

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method UpdateFlow -Params @($Flow.Id, $Flow.Name, $Project.Id, $Owner.Id) 

    return $response, $responseError

}

function global:Find-TSFlow {
    param(
        [Parameter(Mandatory=$false)][object]$Flows,
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][object]$Owner,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )
    if ([string]::IsNullOrEmpty($Id) -and [string]::IsNullOrEmpty($Name) -and [string]::IsNullOrEmpty($Owner)) {
        Write-Host+ "ERROR: The search parameters `$Id, `$Name and `$Owner are null." -ForegroundColor Red
        return
    }
    if (!$Flows) { $Flows = Get-TSFlows }
    $params = @{Operator = $Operator}
    if ($Id) {$params += @{Id = $Id}}
    if ($Name) {$params += @{Name = $Name}}
    if ($Owner) {$params += @{OwnerId = $Owner.id}}
    return Find-TSObject -Type "Flow" -Flows $Flows @Params
}

function global:Get-TSFlowPermissions+ {

    param(
        [Parameter(Mandatory=$false)][object]$Flows = (Get-TSFlows+),
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers)
    )

    if (!$Flows) {throw "Flows is empty"}
    if (!$Groups) {throw "Groups is empty"}
    if (!$Users) {throw "Users is empty"}
    
    $flowPermissions = @{}
    foreach ($flow in $flows) {
        $permissions = Get-TSFlowPermissions -Flow $Flow
        foreach ($defaultPermission in $permissions) {
            $perm = @{flow = $flow; granteeCapabilities = @()}
            foreach ($granteeCapability in $defaultPermission.GranteeCapabilities) { 
                $granteeCapabilityPlus = @{capabilities = $granteeCapability.capabilities}
                if ($granteeCapability.user) {
                    $granteeCapabilityPlus.user = Find-TSUser -Users $users -Id $granteeCapability.user.id
                }
                elseif ($granteeCapability.group) {
                    $granteeCapabilityPlus.group = Find-TSGroup -Groups $groups -Id $granteeCapability.group.id
                }
                $perm.granteeCapabilities += $granteeCapabilityPlus
            }
            $flowPermissions += @{$flow.id = $perm}
        }
    }

    return $flowPermissions
}

function global:Get-TSFlowPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Flow
    )

    return Get-TSObjects -Method GetFlowPermissions -Params @($Flow.Id)
}

function global:Add-TSFlowPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Flow,
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        [Parameter(Mandatory=$false)][string[]]$Capabilities 
    )

    if (!($Group -or $User) -or ($Group -and $User)) {
        throw "Must specify either Group or User"
    }

    
    $Capabilities | Foreach-Object {
        if ($_ -notin $FlowPermissions) {
            throw "$($_) is not a valid capability"
        }
    }  

    $grantee = $Group ?? $User
    $granteeType = $Group ? "group" : "user"
    $capabilityXML = "<$granteeType id='$($grantee.id)'/>"
    
    $capabilityXML += "<capabilities>"
    foreach ($capability in $Capabilities) {
        $name,$mode = $capability -split ":"
        $capabilityXML += "<capability name='$name' mode='$mode'/>"
    }
    $capabilityXML += "</capabilities>"

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "AddFlowPermissions" -Params @($Flow.id,$capabilityXML)
    
    return $response,$responseError
}

#endregion FLOWS
#region METRICS

    function global:Get-TSMetrics {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false)][string]$Filter
        )

        return Get-TSObjects -Method GetMetrics -Filter $Filter
    }

    function global:Get-TSMetric {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)][string]$MetricLuid
        )

        return Get-TSObjects -Method GetMetric -Params @($MetricLuid)
    }

    function global:Update-TSMetric {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)][object]$Metric,
            [Parameter(Mandatory=$false)][object]$Project = $Metric.Project,
            [Parameter(Mandatory=$false)][object]$Owner = $Metric.Owner
        )

        $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method UpdateMetric -Params @($Metric.Id, $Metric.Name, $Project.Id, $Owner.Id) 

        return $response, $responseError

    }

#endregion METRICS
#region COLLECTIONS

    function global:Get-TSCollections {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false)][object]$User=(Get-TSCurrentUser)
        )

        $responseError = "Collections are not yet supported by the Tableau Server REST API."
        Write-Host+ $responseError -ForegroundColor DarkYellow
        Write-Log -EntryType "Warning" -Action "GetCollections" -Target "Collections" -Status "NotSupported" -Message $responseError 
        return

        $collection = Get-TSObjects -Method GetCollections -Params @($User.id)

        return $collection
    }

#endregion COLLECTIONS
#region FAVORITES

function global:Get-TSFavorites+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers),
        [Parameter(Mandatory=$false)][object]$UsersWithFavorites,
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+),
        [Parameter(Mandatory=$false)][object]$Workbooks = (Get-TSWorkbooks+),
        [Parameter(Mandatory=$false)][object]$Views = (Get-TSViews+),
        [Parameter(Mandatory=$false)][object]$Datasources = (Get-TSDatasources+),
        [Parameter(Mandatory=$false)][object]$Flows = (Get-TSFlows+),
        [Parameter(Mandatory=$false)][object]$Metrics = (Get-TSMetrics),
        [Parameter(Mandatory=$false)][object]$Collections = (Get-TSCollections)
    )

    $favoritesPlus = @()
    foreach ($user in ($UsersWithFavorites ?? $Users)) {
        $favorites = Get-TSObjects -Method GetFavorites -Params @($user.id) 
        foreach ($favorite in $favorites) {

            $favoriteType = $null

            $favoritePlus = [PSCustomObject]@{
                favoriteType = $null
                owner = Find-TSUser -Users $Users -Id $user.id
                label = $favorite.label
                position = [int]$favorite.position
                addedat = [datetime]$favorite.addedat
            }

            $favoritePlusMembers = $favoritePlus | Get-Member -MemberType NoteProperty
            $favoriteMembers = $favorite | Get-Member -MemberType Property  | Where-Object {$_.name -notin $favoritePlusMembers.name}
            foreach ($member in  $favoriteMembers) {
                $favoritePlus | Add-Member -NotePropertyName $member.Name -NotePropertyValue $favorite.($member.Name)
                $favoritePlus.favoriteType = $member.Name
            }
            
            switch ($favoriteType) {
                "project" {
                    $favoritePlus.project = Find-TSProject -Projects $Projects -Id $favorite.project.id
                }
                "workbook" {
                    $favoritePlus.workbook = Find-TSWorkbook -Workbooks $Workbooks -Id $favorite.workbook.id
                }
                "view" {
                    $favoritePlus.view = Find-TSView -Views $Views -Id $favorite.view.id
                }
                "datasource" {
                    $favoritePlus.datasource = Find-TSDataSource -Datasources $Datasources -Id $favorite.datasource.id
                }
                "flow" {
                    $favoritePlus.flow = Find-TSFlow -Flows $Flows -Id $favorite.flow.id
                }
                "metric" {}
                "collection" {}
                default {}
            }

            $favoritesPlus += $favoritePlus
        }
    }

    return $favoritesPlus
}

function global:Get-TSFavorites {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$User=(Get-TSCurrentUser)
    )

    $favorite = Get-TSObjects -Method GetFavorites -Params @($User.id)

    return $favorite
}

function global:Find-TSFavorite {
    param(
        [Parameter(Mandatory=$true)][object]$User,
        [Parameter(Mandatory=$false)][object]$Favorites = (Get-TSFavorites -User $User),
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][Alias("Label")][string]$Name,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )
    if ([string]::IsNullOrEmpty($Id) -and [string]::IsNullOrEmpty($Name)) {
        Write-Host+ "ERROR: The search parameters `$Id and `$Name are null." -ForegroundColor Red
        return
    }
    $params = @{Operator = $Operator}
    if ($Id) {$params += @{Id = $Id}}
    if ($Name) {$params += @{Name = $Name}}
    if ($Owner) {$params += @{OwnerId = $Owner.id}}
    return Find-TSObject -Type "Favorite" -Favorites $Favorites @Params
}

function global:Add-TSFavorites {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Favorites
    )

    foreach ($favorite in $favorites) {
        $response,$responseError = Add-TSFavorite -User $favorite.owner -Label $favorite.label -Type $favorite.favoriteType -InputObject $favorite.($favorite.favoriteType)
        if ($responseError.code) {
            return
        }
    }

    return
}

function global:Add-TSFavorite {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$User,
        [Parameter(Mandatory=$true)][string]$Label,
        [Parameter(Mandatory=$true)][string]$Type,
        [Parameter(Mandatory=$true)][Alias("Workbook","View","DataSource","Project","Flow","Metric","Collection")][object]$InputObject
    )

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "AddFavorites" -Params @($User.id,($Label.replace("&","&amp;")),$Type,$InputObject.id)
    if ($responseError.code) {
        return
    }
    
    return $response,$responseError
}

#endregion FAVORITES
#region SCHEDULES

function global:Get-TSSchedules {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method GetSchedules

}

function global:Get-TSSchedule {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id
    )

    return Get-TSObjects -Method GetSchedule -Params @($Id)

}

#endregion SCHEDULES    
#region SUBSCRIPTIONS

function global:Get-TSSubscriptions {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method GetSubscriptions

}

function global:Get-TSSubscription {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id
    )

    return Get-TSObjects -Method GetSubscription -Params @($Id)

}

#endregion SUBSCRIPTIONS 
#region NOTIFICATIONS

function global:Get-TSDataAlerts {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method GetDataAlerts

}

function global:Get-TSDataAlert {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id
    )

    return Get-TSObjects -Method GetDataAlert -Params @($Id)

}

function global:Get-TSUserNotificationPreferences {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method GetUserNotificationPreferences

}

#endregion NOTIFICATIONS
#region WEBHOOKS

function global:Get-TSWebhooks {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method GetWebhooks

}

function global:Get-TSWebhook {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id
    )

    return Get-TSObjects -Method GetWebhook -Params @($Id)

}

#region WEBHOOKS
#region ANALYTICS EXTENSIONS

function Add-TSAnalyticsExtensionsMeta {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline)][object]$InputObject,
        [Parameter(Mandatory=$true)][ValidateSet("Server","Site")][string]$Target
    )

    begin {
    }
    process {
        $dashboardExtensionsTarget = $InputObject
    }
    end {
        $dashboardExtensionsTarget | Add-Member -NotePropertyName "settingsType" -NotePropertyValue $Target
        if ($Target -eq "Site") {
            $dashboardExtensionsTarget | Add-Member -NotePropertyName "site" -NotePropertyValue $global:tsRestApiConfig.ContentUrl
        }
        $dashboardExtensionsTarget | Add-Member -NotePropertyName "server" -NotePropertyValue ([Uri]$global:tsRestApiConfig.Platform.Uri).Host

        return $dashboardExtensionsTarget
    }

}

function global:Get-TSAnalyticsExtensionsConnections {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false,Position=0)][ValidateSet("Site")][string]$Target = "Site"
    )

    $method = "GetAnalyticsExtensionsConnectionsFor$Target"
    $key = ($global:tsRestApiConfig.Method.$method.Response.Keys).Split(".")[0]
    $tsObject = (Get-TSObjects -Method $method)

    return [PSCustomObject]@{ $key = $tsObject } | Add-TSAnalyticsExtensionsMeta -Target $Target

}

function global:Get-TSAnalyticsExtensionsEnabledState {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false,Position=0)][ValidateSet("Site")][string]$Target = "Site"
    )

    $method = "GetAnalyticsExtensionsEnabledStateFor$Target"
    $key = ($global:tsRestApiConfig.Method.$method.Response.Keys).Split(".")[0]
    $tsObject = (Get-TSObjects -Method $method)

    return [PSCustomObject]@{ $key = $tsObject } | Add-TSAnalyticsExtensionsMeta -Target $Target

}

#endregion ANALYTICS EXTENSIONS
#region DASHBOARD EXTENSIONS

function global:Get-TSDashboardExtensionSettings {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][ValidateSet("Server","Site")][string]$Target
    )

    return Get-TSObjects -Method "GetDashboardExtensionSettingsFor$Target" | Add-TSAnalyticsExtensionsMeta -Target $Target


}

function global:Get-TSBlockedDashboardExtensions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false,Position=0)][ValidateSet("Server")][string]$Target = "Server"
    )

    return Get-TSObjects -Method "GetBlockedDashboardExtensionsFor$Target" | Add-TSAnalyticsExtensionsMeta -Target $Target

}

function global:Get-TSAllowedDashboardExtensions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false,Position=0)][ValidateSet("Site")][string]$Target = "Site"
    )

    return Get-TSObjects -Method "GetAllowedDashboardExtensionsFor$Target" | Add-TSAnalyticsExtensionsMeta -Target $Target

}

#endregion DASHBOARD EXTENSIONS
#region CONNECTED APPLICATIONS

function global:Get-TSConnectedApplications {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method "GetConnectedApplications"

}

function global:Get-TSConnectedApplication {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ClientId
    )

    return Get-TSObjects -Method "GetConnectedApplications" -Params @($ClientId)

}

#endregion CONNECTED APPLICATIONS
#region SYNC

function global:Sync-TSGroups {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [switch]$Delta
    )

    $startTime = Get-Date -AsUTC
    $lastStartTime = (Read-Cache "AzureADSyncGroups").LastStartTime ?? [datetime]::MinValue

    $message = "Getting Azure AD groups and users"
    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor Gray

    $message = "<  Group updates <.>48> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    $azureADGroupUpdates,$cacheError = Get-AzureADGroups -Tenant $Tenant -AsArray -After $lastStartTime
    if ($cacheError) { return $cacheError }
    
    $message = "$($emptyString.PadLeft(8,"`b")) $($azureADGroupUpdates.Count)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen

    $message = "<  Groups <.>48> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    $azureADGroups,$cacheError = Get-AzureADGroups -Tenant $Tenant -AsArray
    if ($cacheError) { return $cacheError }

    $message = "$($emptyString.PadLeft(8,"`b")) $($azureADGroups.Count)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    
    $message = "<  Users <.>48> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    $azureADUsers,$cacheError = Get-AzureADUsers -Tenant $Tenant -AsArray
    if ($cacheError) {  return $cacheError }

    $message = "$($emptyString.PadLeft(8,"`b")) $($azureADUsers.Count)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

    Write-Host+
    $message = "<Syncing Tableau Server groups <.>48> PENDING"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    foreach ($contentUrl in $global:AzureADSyncTS.Sites.ContentUrl) {

        Switch-TSSite $contentUrl
        $tsSite = Get-TSSite
        Write-Host+ -NoTrace "  Site: $($tsSite.name)"

        $tsGroups = @()
        $tsGroups += Get-TSGroups | Where-Object {$_.name -in $azureADGroups.displayName -and $_.name -notin $global:tsRestApiConfig.SpecialGroups} | Select-Object -Property *, @{Name="site";Expression={$null}} | Sort-Object -Property name

        $tsGroups += @()
        $tsUsers += Get-TSUsers | Sort-Object -Property name

        foreach ($tsGroup in $tsGroups) {

            Write-Host+ -NoTrace -NoNewLine "    Group: $($tsGroup.name)"

            $azureADGroupToSync = $azureADGroups | Where-Object {$_.displayName -eq $tsGroup.name}
            $tsGroupMembership = Get-TSGroupMembership -Group $tsGroup
            $azureADGroupMembership = $azureADUsers | Where-Object {$_.id -in $azureADGroupToSync.members -and $_.accountEnabled} | Where-Object {![string]::IsNullOrEmpty($_.mail)}

            $tsUsersToAddToGroup = @()
            $tsUsersToAddToGroup += ($tsUsers | Where-Object {$_.name -in $azureADGroupMembership.userPrincipalName -and $_.id -notin $tsGroupMembership.id}) ?? @()

            # remove Tableau Server group members if they do not match any of the Azure AD group members UPN or any of the SMTP proxy addresses
            $tsUsersToRemoveFromGroup = $tsGroupMembership | Where-Object {$_.name -notin $azureADGroupMembership.userPrincipalName} #  -and "smtp:$($_.name)" -notin $azureADGroupMembership.proxyAddresses.ToLower()}

            $newUsers = @()

            # add the Azure AD group member if neither the UPN nor any of the SMTP proxy addresses are a username on Tableau Server
            $azureADUsersToAddToSite = $azureADGroupMembership | 
                # Where-Object {(Get-AzureADUserProxyAddresses -User $_ -Type SMTP -Domain $global:AzureAD.$Tenant.Sync.Source -NoUPN) -notin $tsUsers.name} | 
                    Where-Object {$_.userPrincipalName -notin $tsUsers.name} | 
                        Sort-Object -Property userPrincipalName
                        
            foreach ($azureADUser in $azureADUsersToAddToSite) {

                $params = @{
                    Site = $tsSite
                    Username = $azureADUser.userPrincipalName
                    FullName = $azureADUser.displayName
                    Email = $azureADUser.mail
                    SiteRole = $global:TSSiteRoles.IndexOf($tsGroup.import.siteRole) -ge $global:TSSiteRoles.IndexOf($global:AzureADSyncTS.$($contentUrl).SiteRoleMinimum) ? $tsGroup.import.siteRole : $global:AzureADSyncTS.$($contentUrl).SiteRoleMinimum
                }

                $newUser = Add-TSUserToSite @params
                $newUsers += $newUser

            }

            if ($azureADUsersToAddToSite) {

                $rebuildSearchIndex = Get-PlatformJob -Type RebuildSearchIndex | Where-Object {$_.status -eq "Created"}

                if ($rebuildSearchIndex) {
                    $rebuildSearchIndex = $rebuildSearchIndex[0]
                }
                else {
                    # force a reindex after creating users to ensure that group updates work
                    $rebuildSearchIndex = Invoke-TsmApiMethod -Method "RebuildSearchIndex"
                }

                $rebuildSearchIndex,$timeout = Wait-Platformjob -id $rebuildSearchIndex.id -IntervalSeconds 5 -TimeoutSeconds 60
                if ($timeout) {
                    # Watch-PlatformJob -Id $rebuildSearchIndex.id -Callback "Write-PlatformJobStatusToLog" -NoMessaging
                }
                # Write-PlatformJobStatusToLog -Id $rebuildSearchIndex.id

            }

            foreach ($newUser in $newUsers) {
                $tsUser = Find-TSUser -name $newUser.Name
                $tsUsersToAddToGroup += $tsUser
                $tsUsers += $tsUser
            }

            if ($tsUsersToAddToGroup) {
                Write-Host+ -NoTrace -NoNewLine -NoTimeStamp "  +$($tsUsersToAddToGroup.count) users" -ForegroundColor DarkGreen
                Add-TSUserToGroup -Group $tsGroup -User $tsUsersToAddToGroup
            }
            if ($tsUsersToRemoveFromGroup) {
                Write-Host+ -NoTrace -NoNewLine -NoTimeStamp "  -$($tsUsersToRemoveFromGroup.count) users" -ForegroundColor Red
                Remove-TSUserFromGroup -Group $tsGroup -User $tsUsersToRemoveFromGroup
            }

            Write-Host+

        }

    }

    @{LastStartTime = $startTime} | Write-Cache "AzureADSyncGroups"

    $message = "<Syncing Tableau Server groups <.>48> SUCCESS"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
    Write-Host+

}

function global:Sync-TSUsers {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [switch]$Delta
    )

    $startTime = Get-Date -AsUTC
    $lastStartTime = (Read-Cache "AzureADSyncUsers").LastStartTime ?? [datetime]::MinValue

    $message = "Getting Azure AD users ($($Delta ? "Delta" : "Full"))"
    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor Gray

    $message = "<  User updates <.>48> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    $azureADUsers,$cacheError = Get-AzureADUsers -Tenant $Tenant -AsArray -After ($Delta ? $lastStartTime : [datetime]::MinValue)
    if ($cacheError) {
        Write-Log -Context "AzureADSyncTS" -Action "Get-AzureADUsers" -Target ($Delta ? "Delta" : "Full") -Status $cacheError.code -Message $cacheError.summary -EntryType "Error"
        $message = "  $($emptyString.PadLeft(8,"`b")) ERROR$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor Gray,DarkGray,Red
        $message = "<    Error $($cacheError.code) <.>48> $($($cacheError.summary))"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,Red
        return
    }

    $message = "$($emptyString.PadLeft(8,"`b")) $($azureADUsers.Count)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

    if ($azureADUsers.Count -le 0) {
        Write-Host+
        $message = "<Syncing Tableau Server users <.>48> $($Delta ? 'SUCCESS' : 'CACHE EMPTY')"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($Delta ? "DarkGreen" : "Red")
        Write-Host+
        return
    }

    if ($Delta) {
        Write-Host+
        Write-Host+ -NoTrace "Orphan detection is unavailable with the Delta switch." -ForegroundColor DarkYellow
        Write-Host+
    }    

    Write-Host+
    $message = "<Syncing Tableau Server users <.>48> PENDING"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    foreach ($contentUrl in $global:AzureADSyncTS.Sites.ContentUrl) {

        Switch-TSSite $contentUrl
        $tsSite = Get-TSSite

        [console]::CursorVisible = $false

        $message = "<    $($tssite.name) <.>48> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        $tsUsers = Get-TSUsers | Where-Object {$_.name.EndsWith($global:AzureAD.$Tenant.Sync.Source) -and $_.name -notin $global:tsRestApiConfig.SpecialAccounts} | Sort-Object -Property name

        # check for Tableau Server user names in the Azure AD users' UPN and SMTP proxy addresses
        # $tsUsers = Get-TSUsers | Where-Object {$_.name -in $azureADUsers.userPrincipalName -and $_.name -notin $global:tsRestApiConfig.SpecialAccounts} | Sort-Object -Property name

        # tsUsers whose email has changed:  their tsUser name is not the Azure AD UPN, but it is contained in the Azure AD account's SMTP proxy addresses
        # $tsUsers += Get-TSUsers | Where-Object {$_.name -notin $azureADUsers.userPrincipalName -and $_.name -in $azureADUsersSmtpProxyAddresses -and $_.name -notin $global:tsRestApiConfig.SpecialAccounts} | Sort-Object -Property name

        # orphaned tsUsers (those without an Azure AD account) excluded by the filter above 
        # $tsUsers = Get-TSUsers | Where-Object {($_.name -notin $azureADUsers.userPrincipalName -and $_.name -notin $azureADUsersSmtpProxyAddresses) -and $_.name -notin $global:tsRestApiConfig.SpecialAccounts} | Sort-Object -Property name

        Write-Host+ -NoTrace -NoTimeStamp "$($emptyString.PadLeft(8,"`b")) $($tsUsers.Count)$($emptyString.PadRight(7-$tsUsers.Count.ToString().Length)," ")" -ForegroundColor DarkGreen
        
        $tsUsers | Foreach-Object {

            $tsUser = Get-TSUser -Id $_.id

            $azureADUserAccountAction = "PROFILE"
            $azureADUserAccountActionResult = ""
            $azureADUserAccountState = $tsUser.siteRole -eq "Unlicensed" ? "Disabled" : "Enabled"
            $azureADUserAccountStateColor = "DarkGray";
            $siteRole = $tsUser.siteRole

            # find the Azure AD account (or not), determine the account state, the appropriate account action and set any tsUser properties
            # Azure AD account match: where the Tableau Server user name equals the UPN or is a SMTP address in the proxyAddresses collection
            $azureADUser = $azureADUsers | Where-Object {$_.userPrincipalName -eq $tsUser.name}

            # typical azureADUser and tsUser account scenarios
            # the tsUser's account state should match the azureADUser's account state
            if ($azureADUser) {
                
                # the azureADUser account is enabled; the tsUser account is disabled
                if ($azureADUser.accountEnabled -and $tsUser.siteRole -eq "Unlicensed") {
                    $azureADUserAccountAction = "ENABLE"; $azureADUserAccountState = "Enabled"; $azureADUserAccountActionResult = "Enabled"; $azureADUserAccountStateColor = "DarkGreen"; $siteRole = $tsUser.siteRole
                }

                # the azureADUser account is disabled; the tsUser account is NOT disabled (enabled)
                elseif (!$azureADUser.accountEnabled -and $tsUser.siteRole -ne "Unlicensed") {
                    $azureADUserAccountAction = "DISABLE"; $azureADUserAccountState = "Disabled"; $azureADUserAccountActionResult = "Disabled"; $azureADUserAccountStateColor = "Red"; $siteRole = "Unlicensed"
                }

                # the azureADUser account's state is equivalent to the tsUser account's state 
                else {
                    $azureADUserAccountAction = "PROFILE"; $azureADUserAccountState = $azureADUser.accountEnabled ? "Enabled" : "Disabled"; $azureADUserAccountActionResult = "";  $azureADUserAccountStateColor = "DarkGray"; $siteRole = $tsUser.siteRole
                }

            }

            # special azureADUser and tsUser account scenarios
            # email changes requiring a replacement tsUser account and orphaned tsUser accounts
            elseif ($tsUser.siteRole -ne "Unlicensed") {

                # changes to the email address for an azureADUser account
                # the tsUser account uses the azureADUser account email for the tsUser name
                # the tsUser name is a key field and is immutable
                # thus, the tsUser account where the name is equivalent to the original email
                # must be replaced with a new tsUser account using the new email address
                
                # determining that an azureADUser account's email has changed:
                # no azureADUser account exists with a UPN that matches the tsUser name, and 
                # the tsUser name exists in an azureADUser account's smtp proxy addresses
                
                $azureADUser = $azureADUsers | Where-Object {$tsUser.name -in (Get-AzureADUserProxyAddresses -User $_ -Type SMTP -Domain $global:AzureAD.$Tenant.Sync.Source -NoUPN)}
                if ($azureADUser) {

                    # found the new azureADUser, but don't replace the user until the tsNewUser is created 
                    # Sync-TSUsers will create the new user and leave the old one in place until this point
                    $tsNewUser = Find-TSUser -Name $azureADUser.userPrincipalName

                    # if tsNewUser has been created, proceed with replacing user; otherwise continue to wait
                    $azureADUserAccountAction = "PENDING"; $azureADUserAccountState = "Replaced"; $azureADUserAccountActionResult = "Pending"; $azureADUserAccountStateColor = "DarkBlue"; 
                    if ($tsNewUser) { $azureADUserAccountAction = "REPLACE"; $azureADUserAccountActionResult = "Replaced"}
        
                    $siteRole = $tsUser.siteRole

                }

                # orphaned tsUser accounts (no associated azureADUser account)
                else {

                    # Orphan detection is unavailable when the Delta switch is used.
                    # why? b/c -delta only pulls the latest user updates from the cache and orphan
                    # detection requires the full user cache

                    if (!$Delta) {

                        # if only relying on azureADUsers pulled from AzureADCache then an AzureADCache failure would 
                        # cause Sync-TSUsers to incorrectly categorize tsUsers without Azure AD accounts as false
                        # orphans.  true orphans should [probably] have their tsUser account disabled.  However, 
                        # disabling a tsUser's account (i.e., setting their siteRole to "Unlicensed") requires first 
                        # that the tsUser be removed from all groups.  As there is no persistence of the tsUser's state,
                        # if AzureADCache does fail, then recovery is minimal as disabled false orphans could not be fully
                        # restored without having some record of their previous state (e.g., group membership).

                        # to avoid this, use Get-AzureADUser to query MSGraph directly and confirm whether the tsUser
                        # account has really been orphaned.  NOTE: if AzureADCache does fail, there will be a HUGE list 
                        # of false orphans which would need to be confirmed. calling Get-AzureADUser for every false orphan
                        # would be VERY slow.  there should probably be a governor for this (only X confirmations per pass).

                        $message = ""
                        $azureADUserAccountAction = "ORPHAN?"; $azureADUserAccountState = "Orphaned"; $azureADUserAccountActionResult = "Pending"; $azureADUserAccountStateColor = "DarkGray"; 
                        if ($tsUser.siteRole -ne "Unlicensed") {

                            # query MSGraph directly to confirm orphan
                            $azureADUser = Get-AzureADUser -Tenant $Tenant -User $tsUser.name

                            # found no azureADUser; orphan confirmed
                            # after notification/logging, ORPHAN will be converted into DISABLE
                            if (!$azureADUser) {
                                $azureADUserAccountAction = "ORPHAN+"; $azureADUserAccountState = "Orphaned"; $azureADUserAccountActionResult = "Confirmed"; $azureADUserAccountStateColor = "DarkYellow"; $siteRole = "Unlicensed"
                                $message = "$azureADUserAccountActionResult orphan"
                            }

                            # azureADUser found! no specific action; let the AzureADSync suite should sort it out
                            # however, highlight it and log it as a false orphan in case there's a larger AzureADSync suite issue
                            else {
                                $azureADUserAccountAction = "ORPHAN-"; $azureADUserAccountState = "Orphaned"; $azureADUserAccountActionResult = "Refuted"; $azureADUserAccountStateColor = "DarkYellow"; $siteRole = $tsUser.siteRole
                                $message = "See the following Azure AD account: $Tenant\$($azureADUser.userPrincipalName)."
                            }

                            Write-Log -Action "IsOrphan" -Target "$($global:tsRestApiConfig.ContentUrl)\$($tsUser.name)" -Status $azureADUserAccountActionResult -Message $message -Force 
                        }

                    }

                }

            }

            Write-Host+ -NoTrace "      $($azureADUserAccountAction): $($tsSite.contentUrl)\$($tsUser.name) == $($tsUser.fullName ?? "null") | $($tsUser.email ?? "null") | $($tsUser.siteRole) | AzureAD:$($azureADUserAccountState)" -ForegroundColor $azureADUserAccountStateColor

            # after notification/logging, convert ORPHAN+ to DISABLED
            if ($azureADUserAccountAction -eq "ORPHAN+") {
                $azureADUserAccountAction = "DISABLE"; $azureADUserAccountState = "Disabled"; $azureADUserAccountActionResult = "Disabled"; $azureADUserAccountStateColor = "Red"; $siteRole = "Unlicensed"
            }

            if ($azureADUserAccountAction -eq "REPLACE") {

                # update group membership of new tsUser
                Get-TSUserMembership -User $tsUser | Foreach-Object { Add-TSUserToGroup -Group $_ -User $tsNewUser }
            
                # change content ownership
                Get-TSWorkbooks -Filter "ownerEmail:eq:$($tsUser.email)" | Foreach-Object {Update-TSWorkbook -Workbook $_ -Owner $tsNewUser | Out-Null }
                Get-TSDatasources -Filter "ownerEmail:eq:$($tsUser.email)" | Foreach-Object {Update-TSDatasource -Datasource $_ -Owner $tsNewUser | Out-Null }
                Get-TSFlows -Filter "ownerName:eq:$($tsUser.fullName)" | Foreach-Object {Update-TSFlow -Flow $_ -Owner $tsNewUser | Out-Null }
                Get-TSMetrics -Filter "ownerEmail:eq:$($tsUser.email)" | Foreach-Object {Update-TSMetric -Metric $_ -Owner $tsNewUser | Out-Null }

                Write-Log -Action ((Get-Culture).TextInfo.ToTitleCase($azureADUserAccountAction)) -Target "$($global:tsRestApiConfig.ContentUrl)\$($tsUser.name)" -Status $azureADUserAccountActionResult -Force
                Write-Host+ -NoTrace "      $($azureADUserAccountAction): $($tsSite.contentUrl)\$($tsNewUser.name) << $($tsSite.contentUrl)\$($tsUser.name)" -ForegroundColor DarkBlue

                # set action/state for tsUser to be disabled below
                $azureADUserAccountAction = "DISABLE"; $azureADUserAccountState = "Disabled"; $azureADUserAccountActionResult = "Disabled"; $azureADUserAccountStateColor = "Red"; $siteRole = "Unlicensed"

            }

            # set fullName and email
            $fullName = $azureADUser.displayName ?? $tsUser.fullName
            $email = $azureADUser.mail ?? $($tsUser.email ?? $tsUser.name)
            
            # if changes to fullName, email or siteRole, update tsUser
            # Update-TSUser replaces both apostrophe characters ("'" and "’") in fullName and email with "&apos;" (which translates to "'")
            # Replace "’" with "'" in order to correctly compare fullName and email from $tsUser and $azureADUser 
            
            if ($fullName.replace("’","'") -ne $tsUser.fullName -or $email.replace("’","'") -ne $tsUser.email -or $siteRole -ne $tsUser.siteRole) {

                if ($azureADUserAccountAction -ne "DISABLE") {
                    $azureADUserAccountAction = " UPDATE"; $azureADUserAccountActionResult = "Updated"; $azureADUserAccountStateColor = "DarkGreen"
                }

                # update the user
                $response, $responseError = Update-TSUser -User $tsUser -FullName $fullName -Email $email -SiteRole $siteRole | Out-Null
                if ($responseError) {
                    Write-Log -Action ((Get-Culture).TextInfo.ToTitleCase($azureADUserAccountAction)) -Target "$($tsSite.contentUrl)\$($tsUser.name)" -Message "$($responseError.detail)" -EntryType "Error" -Status "Error"
                    Write-Host+ "      $($response.error.detail)" -ForegroundColor Red
                }
                else {
                    Write-Host+ -NoTrace "      $($azureADUserAccountAction): $($tsSite.contentUrl)\$($tsUser.name) << $fullName | $email | $siteRole" -ForegroundColor $azureADUserAccountStateColor
                    # Write-Log -Action ((Get-Culture).TextInfo.ToTitleCase($azureADUserAccountAction)) -Target "$($global:tsRestApiConfig.ContentUrl)\$($tsUser.name)" -Status $azureADUserAccountActionResult -Force 
                }
            }

        }
    
    }

    @{LastStartTime = $startTime} | Write-Cache "AzureADSyncUsers"

    $message = "<  Syncing Tableau Server users <.>48> SUCCESS"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
    
    Write-Host+

}

#endregion SYNC