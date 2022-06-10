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
    $params = @{}
    if ($Server) { $params += @{Server = $Server} }
    return (IsTableauOnline @params) ? "TableauOnline" : "TableauServer"
}


function IsTableauOnline {
    param(
        [Parameter(Mandatory=$false,Position=0)][string]$Server
    )
    if (!($global:tsRestApiConfig.Platform.id) -and !$Server) {
        throw "`"Server`" must be specified when the Tableau Server REST API platform is undefined."
        return
    }
    if ($Server) { return $Server -like "*online.tableau.com" }
    return $global:tsRestApiConfig.Platform.Id -eq "TableauOnline"
}

function IsPlatformServer {
    param()
    return $Server -eq "localhost" -or $Server -eq $global:Platform.Uri.Host
}

function global:Initialize-TSRestApiConfiguration {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Server = "localhost",
        [Parameter(Mandatory=$false)][Alias("Site")][string]$ContentUrl = "",
        [Parameter(Mandatory=$false)][string]$Credentials = "localadmin-$($Platform.Instance)",
        [switch]$Reset
    )

    if ($Reset) {
        $global:tsRestApiConfig = @{}
    }

    $global:tsRestApiConfig = @{
        Server = $Server ? $Server : ($tsmApiConfig.Server ? $tsmApiConfig.Server : "localhost")
        Credentials = $Credentials
        Token = $null
        SiteId = $null
        ContentUrl = $ContentUrl
        ContentType = "application/xml;charset=utf-8"
        UserId = $null
        SpecialAccounts = @("guest","tableausvc","TabSrvAdmin","alteryxsvc")
        SpecialGroups = @("All Users")
        SpecialMethods = @("ServerInfo","Login")
    }

    $global:tsRestApiConfig.RestApiVersioning = @{
        ApiVersion = "3.15"
        Headers = @{
            "Accept" = "*/*"
            "Content-Type" = "application/xml;charset=utf-8"
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

    
    $global:tsRestApiConfig.Method = @{
        Login = @{
            Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/auth/signin"
            HttpMethod = "POST"
            Body = "<tsRequest><credentials name='<0>' password='<1>'><site contentUrl='<2>'/></credentials></tsRequest>"
            Response = @{Keys = "credentials"}
        } 
        ServerInfo = @{
            Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/serverinfo"
            HttpMethod = "GET"
            Response = @{Keys = "serverinfo"}
        }
    }

    $creds = Get-Credentials $global:tsRestApiConfig.Credentials

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method Login -Params @($creds.UserName,$creds.GetNetworkCredential().Password,$global:tsRestApiConfig.ContentUrl)
    if ($responseError) {throw $responseError}

    $global:tsRestApiConfig.Token = $response.token
    $global:tsRestApiConfig.SiteId = $response.site.id
    $global:tsRestApiConfig.ContentUrl = $response.site.contentUrl
    $global:tsRestApiConfig.UserId = $response.user.id 

    $serverInfo = Get-TsServerInfo
    
    $global:tsRestApiConfig.RestApiVersioning = @{
        ApiVersion = $serverInfo.restApiVersion
        Headers = @{
            "Accept" = "*/*"
            "Content-Type" = "application/xml;charset=utf-8"
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

    if (IsPlatformServer) {
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
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/auth/signin"
                HttpMethod = "POST"
                Body = "<tsRequest><credentials name='<0>' password='<1>'><site contentUrl='<2>'/></credentials></tsRequest>"
                Response = @{Keys = "credentials"}
            } 
            GetCurrentSession = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sessions/current"
                HttpMethod = "GET"
                Response = @{Keys = "session"}
            }
            Logout = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/auth/signout"
                HttpMethod = "POST"
            }

        #endregion SESSION METHODS
        #region SERVER METHODS

            ServerInfo = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/serverinfo"
                HttpMethod = "GET"
                Response = @{Keys = "serverinfo"}
            }
            GetDomains = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/domains"
                HttpMethod = "GET"
                Response = @{Keys = "domainList"}
            }

        #endregion SERVER METHODS
        #region GROUP METHODS

            GetGroups = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/groups"
                HttpMethod = "GET"
                Response = @{Keys = "groups.group"}
            }
            AddGroupToSite = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/groups"
                HttpMethod = "POST"
                Body = "<tsRequest><group name='<0>'/></tsRequest>"
                Response = @{Keys = "group"}
            }
            RemoveGroupFromSite = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/groups/<0>"
                HttpMethod = "DELETE"
                Response = @{Keys = "group"}
            }
            GetGroupMembership = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/groups/<0>/users"
                HttpMethod = "GET"
                Response = @{Keys = "users.user"}
            }
            AddUserToGroup = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/groups/<0>/users"
                HttpMethod = "POST"
                Body = "<tsRequest><user id='<1>'/></tsRequest>"
                Response = @{Keys = "user"}
            }
            RemoveUserFromGroup = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/groups/<0>/users/<1>"
                HttpMethod = "DELETE"
                Response = @{Keys = ""}
            }

        #endregion GROUP METHODS
        #region SITE METHODS

            SwitchSite = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/auth/switchSite"
                HttpMethod = "POST"
                Body = "<tsRequest><site contentUrl='<0>'/></tsRequest>"
                Response = @{Keys = "credentials"}
            } 
            GetSites = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites"
                HttpMethod = "GET"
                Response = @{Keys = "sites.site"}
            }
            GetSite = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)"
                HttpMethod = "GET"
                Response = @{Keys = "site"}
            }

        #endregion SITE METHODS
        #region USER METHODS

            GetUsers = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/users"
                HttpMethod = "GET"
                Response = @{Keys = "users.user"}
            }
            GetUser = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/users/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "user"}
            }
            AddUser = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/users"
                HttpMethod = "POST"
                Body = "<tsRequest><user name='<0>' siteRole='<1>' /></tsRequest>"
                Response = @{Keys = "user"}
            }
            RemoveUser = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/users/<0>"
                HttpMethod = "DELETE"
                Response = @{Keys = ""}
            }
            UpdateUser = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/users/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><user fullName='<1>' email='<2>' siteRole='<3>' /></tsRequest>"
                Response = @{Keys = "user"}
            }
            UpdateUserPassword = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/users/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><user password='<1>' /></tsRequest>"
                Response = @{Keys = "user"}
            }
            GetUserMembership = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/users/<0>/groups"
                HttpMethod = "GET"
                Response = @{Keys = "groups.group"}
            }

        #endregion USER METHODS
        #region PROJECT METHODS 
            
            GetProjects = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/projects"
                HttpMethod = "GET"
                Response = @{Keys = "projects.project"}
            }
            GetProjectPermissions = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }
            GetProjectDefaultPermissions = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/default-permissions/<1>"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }
            AddProjectPermissions = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }
            AddProjectDefaultPermissions = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/default-permissions/<1>"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><2></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }
            RemoveProjectPermissions = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/permissions/<1>/<2>/<3>/<4>"
                HttpMethod = "DELETE"
                Response = @{Keys = "permissions"}
            }
            RemoveProjectDefaultPermissions = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/default-permissions/<1>/<2>/<3>/<4>/<5>"
                HttpMethod = "DELETE"
                Response = @{Keys = "permissions"}
            }

        #endregion PROJECT METHODS
        #region WORKBOOK METHODS

            GetWorkbooks = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks"
                HttpMethod = "GET"
                Response = @{Keys = "workbooks.workbook"}
            }
            GetWorkbook = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "workbook"}
            }
            GetWorkbookRevisions = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/revisions"
                HttpMethod = "GET"
                Response = @{Keys = "revisions.revision"}
            }
            GetWorkbookPermissions = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }   
            AddWorkbookPermissions = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }
            GetWorkbookConnections = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/connections"
                HttpMethod = "GET"
                Response = @{Keys = "connections.connection"}
            }

        #endregion WORKBOOK METHODS
        #region VIEW METHODS 

            GetViewsForSite = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/views"
                HttpMethod = "GET"
                Response = @{Keys = "views.view"}
            }
            GetViewsForWorkbook = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/views"
                HttpMethod = "GET"
                Response = @{Keys = "views.view"}
            }
            GetViewPermissions = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/views/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }   
            AddViewPermissions = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/views/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }

        #endregion VIEW METHODS 
        #region DATASOURCE METHODS 

            GetDataSource = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "datasource"}
            }
            GetDataSources = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/datasources"
                HttpMethod = "GET"
                Response = @{Keys = "datasources.datasource"}
            }
            GetDatasourcePermissions = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }
            AddDataSourcePermissions = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }
            GetDataSourceRevisions = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>/revisions"
                HttpMethod = "GET"
                Response = @{Keys = "revisions.revision"}
            }
            GetDataSourceConnections = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>/connections"
                HttpMethod = "GET"
                Response = @{Keys = "connections.connection"}
            }

        #endregion DATASOURCE METHODS
        #region FLOW METHODS

            GetFlows = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/flows"
                HttpMethod = "GET"
                Response = @{Keys = "flows.flow"}
            }
            GetFlow = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/flows/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "flow"}
            }
            GetFlowPermissions = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/flows/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }
            AddFlowPermissions = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/flows/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }

        #endregion FLOW METHODS          
        #region METRIC METHODS

            GetMetrics = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/metrics"
                HttpMethod = "GET"
                Response = @{Keys = "metrics.metric"}
            }
            GetMetric = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/metrics/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "metrics.metric"}
            }

        #endregion METRIC METHODS
        #region FAVORITE METHODS

            GetFavorites = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/favorites/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "favorites.favorite"}
            }
            AddFavorites = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/favorites/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><favorite label='<1>'><<2> id='<3>'/></favorite></tsRequest>"
                Response = @{Keys = "favorites.favorite"}
            }

        #endregion FAVORITE METHODS
        #region SCHEDULES

            GetSchedules = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/schedules"
                HttpMethod = "GET"
                Response = @{Keys = "schedules.schedule"}
            }
            GetSchedule = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/schedules/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "schedule"}
            }
        
        #endregion SCHEDULES
        #region SUBSCRIPTIONS

            GetSubscriptions = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/subscriptions"
                HttpMethod = "GET"
                Response = @{Keys = "subscriptions.subscription"}
            }
            GetSubscription = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/subscriptions/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "subscription"}
            }

        #endregion SUBSCRIPTIONS
        #region NOTIFICATIONS
            
            GetDataAlerts = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/dataAlerts"
                HttpMethod = "GET"
                Response = @{Keys = "dataAlerts.dataAlert"}
            }
            GetWebhooks = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/webhooks"
                HttpMethod = "GET"
                Response = @{Keys = "webhooks.webhook"}
            }
            GetWebhook = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/webhooks/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "webhook"}
            }
            GetUserNotificationPreferences = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/settings/notifications"
                HttpMethod = "GET"
                Response = @{Keys = "userNotificationsPreferences.userNotificationsPreference"}
            }

        #endregion NOTIFICATIONS
        #region ANALYTICS EXTENSIONS

            GetAnalyticsExtensionsConnectionsForSite = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/-/settings/site/extensions/analytics/connections"
                HttpMethod = "GET"
                Response = @{Keys = "connectionList"}
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
                VersioningType = $EndpointVersioningType.PerResourceVersioning
            }
            GetAnalyticsExtensionsEnabledStateForSite = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/-/settings/site/extensions/analytics"
                HttpMethod = "GET"
                Response = @{Keys = "enabled"}
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
                VersioningType = $EndpointVersioningType.PerResourceVersioning
            }  

        #endregion ANALYTICS EXTENSIONS
        #region DASHBOARD EXTENSIONS

            GetDashboardExtensionSettingsForServer = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/-/settings/server/extensions/dashboard"
                HttpMethod = "GET"
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
                VersioningType = $EndpointVersioningType.PerResourceVersioning
            } 
            GetBlockedDashboardExtensionsForServer = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/-/settings/server/extensions/dashboard/blockListItems"
                HttpMethod = "GET"
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
                VersioningType = $EndpointVersioningType.PerResourceVersioning
            }  
            GetDashboardExtensionSettingsForSite = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/-/settings/site/extensions/dashboard"
                HttpMethod = "GET"
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
                VersioningType = $EndpointVersioningType.PerResourceVersioning
            } 
            GetAllowedDashboardExtensionsForSite = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/-/settings/site/extensions/dashboard/safeListItems"
                HttpMethod = "GET"
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
                VersioningType = $EndpointVersioningType.PerResourceVersioning
            }

        #endregion DASHBOARD EXTENSIONS
        #region CONNECTED APPLICATIONS

            GetConnectedApplications = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/connected-applications"
                HttpMethod = "GET"
                Response = @{Keys = "connectedApplications.connectedApplication"}
            }
            GetConnectedApplication = @{
                Path = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)/connected-applications/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "connectedApplications.connectedApplication"}
            }

        #endregion CONNECTED APPLICATIONS

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
        [Parameter(Mandatory=$false)][string]$FilterExpression
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    if ($Method -notin $global:tsRestApiConfig.SpecialMethods -and !$global:tsRestApiConfig.Token) {
        $responseError = @{
            code = "401002"
            summary = "Unauthorized Access"
            detail = "Invalid authentication credentials were provided"
        }
        $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
        Write-Host+ $errorMessage -ForegroundColor Red
        Write-Log -Message $errorMessage -EntryType "Error" -Action "TSRestApiMethod" -Target $Method -Status "Error"
        return $null, $null, $responseError
    }

    $responseRoot = (IsRestApiVersioning -Method $Method) ? "tsResponse" : $null
    
    $pageFilter = "pageNumber=$($PageNumber)&pageSize=$($PageSize)"
    $filter = $FilterExpression ? "?filter=$($FilterExpression)&$($pageFilter)" : "?$($pageFilter)"

    $httpMethod = $global:tsRestApiConfig.Method.$Method.HttpMethod

    $path = "$($global:tsRestApiConfig.Method.$Method.Path)"
    $path += (IsRestApiVersioning -Method $Method) -and $httpMethod -eq "GET" ? $filter : $null

    $body = $global:tsRestApiConfig.Method.$Method.Body 

    $headers = $global:tsRestApiConfig.(Get-VersioningType -Method $Method).Headers | Copy-Object
    $headers."Content-Type" = $headers."Content-Type".Replace("<ResourceString>",$global:tsRestApiConfig.Method.$Method.ResourceString)

    $keys = $global:tsRestApiConfig.Method.$Method.Response.Keys
    # $tsObjectName = $keys ? $keys.split(".")[-1] : "response"

    for ($i = 0; $i -lt $Params.Count; $i++) {
        $path = $path -replace "<$($i)>",$Params[$i]
        $body = $body -replace "<$($i)>",$Params[$i]
        $keys = $keys -replace "<$($i)>",$Params[$i]
    }  
    
    try {
        $response = Invoke-RestMethod -Uri $path -Method $httpMethod -Headers $headers -Body $body -TimeoutSec 15 -SkipCertificateCheck -SkipHttpErrorCheck -Verbose:$false -ResponseHeadersVariable responseHeaders
        $responseError = $null
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
        $responseError = $_.Exception.Message
    }

    if ($responseError) {
        $errorMessage = $responseError
        if ($responseError.code) {
            $errorMessage = "Error $($responseError.code)$((IsRestApiVersioning -Method $Method) ? " $($responseError.summary)" : $null): $($responseError.detail)"
        }
        Write-Host+ $errorMessage -ForegroundColor Red
        Write-Log -Action $Method -Status "Error" -EntryType "Error" -Message $errorMessage
        # return $response, $null, $responseError
        throw $errorMessage
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

    $tsObject = $response | Copy-Object
    $keys = $keys ? "$($responseRoot)$($responseRoot ? "." : $null)$($keys)" : $responseRoot
    if ($keys) {
        foreach ($key in $keys.split(".")) {
            $tsObject = $tsObject.$key
        }
    }

    $pagination.CountThisPage = $tsObject.Count
    $pagination.TotalReturned = ((($PageNumber - 1) * $PageSize) + $pagination.CountThisPage)

    # if ([string]::IsNullOrEmpty($tsObject)) {
    #     $errorMessage = "$tsObjectName object is null"
    #     Write-Host+ $errorMessage -ForegroundColor DarkGray
    # }

    return $tsObject, $pagination, $responseError

}

function global:Download-TSObject {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Method,
        [Parameter(Mandatory=$true)][System.Xml.XmlElement]$InputObject
    )

    if ($Method -notin $global:tsRestApiConfig.SpecialMethods -and !$global:tsRestApiConfig.Token) {
        $responseError = @{
            code = "401002"
            summary = "Unauthorized Access"
            detail = "Invalid authentication credentials were provided"
        }
        $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
        # Write-Host+ $errorMessage -ForegroundColor Red
        Write-Log -Message $errorMessage -EntryType "Error" -Action "TSRestApiMethod" -Target $Method -Status "Error"
        return $null, $null, $responseError
    }

    $tsObjectType = $global:tsRestApiConfig.Method.$Method.Response.Keys.Split(".")[-1]

    $projectPath = ""
    $projects = Get-TSProjects
    $project = $projects | Where-Object {$_.id -eq $InputObject.project.id}
    do {
        $projectPath = $project.Name + ($projectPath ? "\" : $null) + $projectPath
        $project = $projects | Where-Object {$_.id -eq $project.parentProjectId}
    } until (!$project)

    $contentUrl = ![string]::IsNullOrEmpty($global:tsRestApiConfig.ContentUrl) ? $global:tsRestApiConfig.ContentUrl : "default"
    $outFileDirectory = "$($global:Location.Root)\Data\$($global:tsRestApiConfig.Platform.Instance)\.export\$contentUrl\$projectPath"
    if (!(Test-Path $outFileDirectory)) { New-Item -ItemType Directory -Path $outFileDirectory | Out-Null }

    $httpMethod = $global:tsRestApiConfig.Method.$Method.HttpMethod
    $path = "$($global:tsRestApiConfig.Method.$Method.Path)/content" -replace "<0>",$InputObject.Id
    
    $headers = $global:tsRestApiConfig.(Get-VersioningType -Method $Method).Headers | Copy-Object
    $headers."Content-Type" = $headers."Content-Type".Replace("<ResourceString>",$global:tsRestApiConfig.Method.$Method.ResourceString)

    try {
        $response = Invoke-RestMethod -Uri $path -Method $httpMethod -Headers $headers -TimeoutSec 15 -SkipCertificateCheck -SkipHttpErrorCheck -Verbose:$false -ResponseHeadersVariable responseHeaders
        $responseError = $null
        if (IsRestApiVersioning -Method $Method) {
            $responseError = $response.$responseRoot.error 
        }
        else {
            if ($response.httpErrorCode) {
                $responseError = [System.Collections.Specialized.OrderedDictionary]@{}
                $responseError += @{
                    code = $response.httpErrorCode
                    detail = $response.message
                }
            }
        }
    }
    catch {
        $responseError = $_.Exception.Message
    }

    if ([string]::IsNullOrEmpty($responseHeaders."Content-Disposition")) {
        $responseError = [System.Collections.Specialized.OrderedDictionary]@{}
        $responseError += @{
            code = 404
            summary = "Not Found"
            detail = "$((Get-Culture).TextInfo.ToTitleCase($tsObjectType)) download failed"
        }
    } 

    if ($responseError) {
        return @{ error = $responseError }
    }         

    # $contentType = $responseHeaders."Content-Type"
    $contentDisposition = $responseHeaders."Content-Disposition".Split("; ")
    $outFileName = $contentDisposition[1].Split("=")[1].Replace("`"","")
    $outFile = "$outFileDirectory\$outFileName"

    Remove-Variable $responseHeaders

    $responseError = $null
    try {
        $response = Invoke-RestMethod -Uri $path -Method $httpMethod -Headers $headers -TimeoutSec 15 -SkipCertificateCheck -SkipHttpErrorCheck -Verbose:$false -OutFile $outFile
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
        $responseError = $_.Exception.Message
    }

    if ($responseError) {
        return @{ error = $responseError }
    }  

    return @{
        outFile = $outFile
    }

}

#endregion INVOKE

#region SESSION

function global:Connect-TableauServer {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Server = "localhost",
        [Parameter(Mandatory=$false,Position=1)][Alias("Site")][string]$ContentUrl
    )

    Initialize-TSRestApiConfiguration $Server
    if ($ContentUrl) {Switch-TSSite $ContentUrl}

    return
}

function global:Get-TSCurrentSession {

    [CmdletBinding()]
    param()

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    return Get-TSObjects -Method GetCurrentSession

}

function global:Disconnect-TableauServer {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Server = "localhost"
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
    param(
        # [switch][Alias("ResetCache")]$Update
    )

    # if (!$Update) {
    #     if ($(get-cache platforminfo ).Exists()) {
    #         $platformInfo = Read-Cache platforminfo 
    #         if ($platformInfo) {
    #             $global:Platform.Version = $platformInfo.Version
    #             $global:Platform.Build = $platformInfo.Build
    #             $global:Platform.Api.TsRestApiVersion = $platformInfo.TsRestApiVersion
    #             return
    #         }
    #     }
    # }

    return Get-TSObjects -Method ServerInfo
    # Write-Host+ -NoTrace -NoTimestamp -Iff (!$response) "Unable to connect to Tableau Server REST API." -ForegroundColor Red

    # if ($response -and $Update) {
    #     $global:Platform.Api.TsRestApiVersion = $response.restApiVersion
    #     $global:Platform.Version = $response.productVersion.InnerText
    #     $global:Platform.Build = $response.productVersion.build
    #     Write-Cache platforminfo -InputObject @{Version=$global:Platform.Version;Build=$global:Platform.Build;TsRestApiVersion=$global:Platform.Api.TsRestApiVersion}
    # }

    # return $response

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
        [Parameter(Mandatory=$false)][string]$FilterExpression,
        [switch]$Download
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $objects = @()

    $pageNumber = 1
    $pageSize = 100

    do {
        $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method $Method -Params $Params -FilterExpression $FilterExpression -PageNumber $pageNumber -PageSize $pageSize
        if ($responseError) {
            $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
            Write-Host+ -NoTrace $errorMessage -ForegroundColor Red
            Write-Log -Message $errorMessage -EntryType "Error" -Action $Method -Status "Error"
            return
        }
        $objects += $response
        $pagenumber += 1
    } until ($pagination.IsLastPage)

    if ($objects -and $Download) {
        foreach ($object in $objects) {
            $response = Download-TSObject -Method ($Method -replace "s$","") -InputObject $object
            if ($response.error) {
                $errorMessage = "Error $($response.error.code) ($($response.error.summary)): $($response.error.detail)"
                # Write-Host+ -NoTrace $errorMessage -ForegroundColor Red
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

    # if (IsTableauOnline) { return }

    if ($ContentUrl -notin (Get-TSSites).contentUrl) {    
        $message = "Site `"$ContentUrl`" is not a valid contentURL for a site on $($global:tsRestApiConfig.Server)"
        Write-Host+ $message -ForegroundColor Red
        Write-Log -Message $message -EntryType "Error" -Action "SwitchSite" -Target $ContentUrl -Status "Error"
        return
    }

    if ($ContentUrl -eq $global:tsRestApiConfig.ContentUrl) {return}

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "SwitchSite" -Params @($ContentUrl)
    if ($responseError) {
        # $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
        # Write-Host+ -NoTrace $errorMessage -ForegroundColor Red
        # Write-Log -Message $errorMessage -EntryType "Error" -Action "SwitchSite" -Status "Error"
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
            "Content-Type" = "application/xml;charset=utf-8"
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

    if (IsTableauOnline) { return Get-TSSite }

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
        [Parameter(Mandatory=$false)][object]$Sites = (Get-TSSites),
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$ContentUrl,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )
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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    return (Get-TSCurrentSession).user

}

function global:Find-TSUser {
    param(
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers),
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )
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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    if ([string]::IsNullOrEmpty($FullName)) {
        $errorMessage = "$($Site.contentUrl)\$Username : FullName is missing or invalid."
        Write-Log -Message $errorMessage.Split(":")[1].Trim() -EntryType "Error" -Action "AddUser" -Target "$($Site.contentUrl)\$($tsSiteUser.name)" -Status "Error" 
        # Write-Host+ -NoTrace "      $errorMessage" -ForegroundColor Red
        return
    }
    if ([string]::IsNullOrEmpty($Email)) {
        $errorMessage = "$($Site.contentUrl)\$Username : Email is missing or invalid."
        Write-Log -Message $errorMessage.Split(":")[1].Trim() -EntryType "Error" -Action "AddUser" -Target "$($Site.contentUrl)\$($tsSiteUser.name)" -Status "Error" 
        # Write-Host+ -NoTrace "      $errorMessage" -ForegroundColor Red
        return
    }

    $SiteRole = $SiteRole -in $global:TSSiteRoles ? $SiteRole : "Unlicensed"

    # $response is a user object or an error object
    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "AddUser" -Params @($Username,$SiteRole)
    if ($responseError) { #}.code -eq "401002") {
        # $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
        # Write-Host+ $errorMessage -ForegroundColor Red
        # Write-Log -Message $errorMessage -EntryType "Error" -Action "AddUser" -Status "Error"
        return
    }
    else {
        $tsSiteUser = $response # $response is a user object
        Write-Log -Action "AddUser" -Target "$($Site.contentUrl)\$($tsSiteUser.name)" -Message "$($tsSiteUser.fullName) | $(![string]::IsNullOrEmpty($tsSiteUser.email) ? "$($tsSiteUser.email) | " : $null)$($tsSiteUser.siteRole)" -Force 
        
        # $response is an update object (NOT a user object) or an error object
        $response = Update-TSSiteUser -User $tsSiteUser -FullName $FullName -Email $Email -SiteRole $SiteRole
        if (!$response.error.code) {
            # $response is an update object (NOT a user object) or an error object
            $response = Update-TSSiteUserPassword -User $tsSiteUser -Password (New-RandomPassword -ExcludeSpecialCharacters)
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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

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
    if ($responseError) { #}.code -eq "401002") {
        # $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
        # Write-Host+ $errorMessage -ForegroundColor Red
        # Write-Log -Message $errorMessage -EntryType "Error" -Action $action -Status "Error"
        return
    }
    else {
        Write-Log -Action $action -Target "$($global:tsRestApiConfig.ContentUrl)\$($User.name)" -Message $update -Force 
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
        [Parameter(Mandatory=$false)][string]$Password
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    # $response is an update object (NOT a user object) or an error object
    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "UpdateUserPassword" -Params @($User.id,$Password)
    if ($responseError) { #}.code -eq "401002") {
        # $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
        # Write-Host+ $errorMessage -ForegroundColor Red
        # Write-Log -Message $errorMessage -EntryType "Error" -Action "UpdateUserPassword" -Status "Error"
        return
    }
    else {
        Write-Log -Action "UpdateUserPassword" -Target "$($global:tsRestApiConfig.ContentUrl)\$($User.name)" -Force 
    }

    # $response is an update object or an error object
    return $response

}
Set-Alias -Name Update-TSSiteUserPassword -Value Update-TSUserPassword -Scope Global

function global:Remove-TSUser {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Site,
        [Parameter(Mandatory=$true)][object]$User
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    # Switch-TSSite $tsSite.contentUrl

    $response, $pagination, $responseError = Invoke-TsRestApiMethod -Method "RemoveUser" -Params @($User.Id)
    if ($responseError) { #}.code -eq "401002") {
        # $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
        # Write-Host+ $errorMessage -ForegroundColor Red
        # Write-Log -Message $errorMessage -EntryType "Error" -Action "RemoveUser" -Status "Error"
        # return
    }
    else {
        Write-Log -Action "RemoveUser" -Target "$($global:tsRestApiConfig.ContentUrl)\$($User.name)" -Force 
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
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )
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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    # $usersAddedToGroup = 0
    $User | ForEach-Object {
        $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "AddUserToGroup" -Params @($Group.Id,$_.Id)
        if ($responseError) { #}.code -eq "401002") {
            # $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
            # Write-Host+  $errorMessage -ForegroundColor Red
            # Write-Log -Message $errorMessage -EntryType "Error" -Action "AddUserToGroup" -Status "Error"
            return
        }
        else {
            # $usersAddedToGroup += 1
            # Write-Log -Action "AddUserToGroup" -Target "$($global:tsRestApiConfig.ContentUrl)\$($Group.name)\$($_.Name)" -Status "+$($usersAddedToGroup)" -Force
            Write-Log -Action "AddUserToGroup" -Target "$($global:tsRestApiConfig.ContentUrl)\$($Group.name)\$($_.Name)" -Force
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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    # $usersRemovedFromGroup = 0
    $User | ForEach-Object {
        $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "RemoveUserFromGroup" -Params @($Group.Id,$_.Id)
        if ($responseError) { #}.code -eq "401002") {
            # $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
            # Write-Host+ $errorMessage -ForegroundColor Red
            # Write-Log -Message $errorMessage -EntryType "Error" -Action "RemoveUserFromGroup" -Status "Error"
            return
        }
        else {
            # $usersRemovedFromGroup += 1
            # Write-Log -Action "RemoveUserFromGroup" -Target "$($global:tsRestApiConfig.ContentUrl)\$($Group.name)\$($_.Name)" -Status "-$($usersRemovedFromGroup)" -Force
            Write-Log -Action "RemoveUserFromGroup" -Target "$($global:tsRestApiConfig.ContentUrl)\$($Group.name)\$($_.Name)" -Force
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
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects)
    )

    if (!$Projects) {
        # Write-Host+ "No projects found in site $($tsRestApiConfig.ContentUrl)" -ForegroundColor DarkGray
        return
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
    param()

    return Get-TSObjects -Method GetProjects

}

function global:Find-TSProject {
    param(
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+),
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )
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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

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
        [Parameter(Mandatory=$false)][object]$Workbooks = (Get-TSWorkbooks -Download:$Download.IsPresent),
        [Parameter(Mandatory=$false)][switch]$Download
    )

    if (!$Workbooks) {
        # Write-Host+ "No workbooks found in site $($tsRestApiConfig.ContentUrl)" -ForegroundColor DarkGray
        return
    }

    $workbookPermissions = Get-TSWorkbookPermissions+ -Users $Users -Groups $Groups -Workbooks $Workbooks

    $workbooksPlus = @()
    $Workbooks | ForEach-Object {
        $workbook = @{}
        $workbookMembers = $_ | Get-Member -MemberType Property
        foreach ($member in  $workbookMembers) {
            $workbook.($member.Name) = $_.($member.Name)
        }
        $workbook.owner = Find-TSUser -Users $Users -Id $_.owner.id
        $workbook.project = Find-TSProject -Projects $Projects -Id $_.project.id
        $workbook.granteeCapabilities = $workbookPermissions.$($_.id).granteeCapabilities
        $workbook.revisions = Get-TSWorkbookRevisions -Id $_.id
        $workbook.connections = Get-TSWorkbookConnections -Id $_.id
        $workbooksPlus += $workbook
    }

    return $workbooksPlus
}

function global:Get-TSWorkbooks {

    [CmdletBinding()]
    param(
        [switch]$Download
    )

    $params = @{}
    if ($Download) { $params += @{ Download = $true } }

    return Get-TSObjects -Method GetWorkbooks @Params

}

function global:Get-TSWorkbook {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [switch]$Download
    )

    $params = @{ Params = @($Id) }
    if ($Download) { $params += @{ Download = $true } }

    return Get-TSObjects -Method GetWorkbook @Params

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
        [Parameter(Mandatory=$false)][object]$Workbooks = (Get-TSWorkbooks),
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][object]$Owner,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )
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

    return Get-TSObjects -Method GetWorkbookPermissions -Params @($Workbook.Id)
}

function global:Add-TSWorkbookPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Workbook,
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        [Parameter(Mandatory=$false)][string[]]$Capabilities 
    )

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
        [Parameter(Mandatory=$true,Position=0)][string]$Id
    )

    return Get-TSObjects -Method GetWorkbookRevisions -Params @($Id)

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
        # Write-Host+ "No views found in site $($tsRestApiConfig.ContentUrl)" -ForegroundColor DarkGray
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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

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
        [Parameter(Mandatory=$false)][object]$Views = (Get-TSViews),
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][object]$Owner,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )
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

    return Get-TSObjects -Method GetViewPermissions -Params @($View.Id)
}

function global:Add-TSViewPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$View,
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        [Parameter(Mandatory=$false)][string[]]$Capabilities 
    )

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
        [Parameter(Mandatory=$false)][object]$Datasources = (Get-TSDatasources -Download:$Download.IsPresent),
        [Parameter(Mandatory=$false)][switch]$Download
    )

    if (!$Datasources) {
        # Write-Host+ "No datasources found in site $($tsRestApiConfig.ContentUrl)" -ForegroundColor DarkGray
        return
    }
    
    $datasourcePermissions = Get-TSDatasourcePermissions+ -Users $Users -Groups $Groups -Datasource $Datasources

    $datasourcesPlus = @()
    $Datasources | ForEach-Object {
        $datasource = @{}
        $datasourceMembers = $_ | Get-Member -MemberType Property
        foreach ($member in  $datasourceMembers) {
            $datasource.($member.Name) = $_.($member.Name)
        }
        $datasource.owner = Find-TSUser -Users $Users -Id $_.owner.id
        $datasource.project = Find-TSProject -Projects $Projects -Id $_.project.id
        $datasource.granteeCapabilities = $datasourcePermissions.$($_.id).granteeCapabilities
        $datasource.revisions = Get-TSDataSourceRevisions -Id $_.id
        $datasource.connections = Get-TSDataSourceConnections -Id $_.id
        $datasourcesPlus += $datasource
    }

    return $datasourcesPlus
}

function global:Get-TSDataSources {

    [CmdletBinding()]
    param(
        [switch]$Download
    )

    $params = @{}
    if ($Download) { $params += @{ Download = $true } }

    return Get-TSObjects -Method GetDatasources @Params

}

function global:Get-TSDataSource {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [switch]$Download
    )

    $params = @{ Params = @($Id) }
    if ($Download) { $params += @{ Download = $true } }

    return Get-TSObjects -Method GetDataSource @Params
}

function global:Get-TSDataSourceRevisions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id
    )

    return Get-TSObjects -Method GetDataSourceRevisions -Params @($Id)
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
        [Parameter(Mandatory=$false)][object]$Datasources = (Get-TSDatasources),
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][object]$Owner,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )
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
        [Parameter(Mandatory=$false)][switch]$Download
    )

    $flows = Get-TSFlows -Download:$Download.IsPresent
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
        [switch]$Download
    )

    $flows = @()
    foreach ($flow in Get-TSObjects -Method GetFlows) {
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

function global:Find-TSFlow {
    param(
        [Parameter(Mandatory=$false)][object]$Flows = (Get-TSFlows),
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][object]$Owner,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )
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
    param()

    return Get-TSObjects -Method GetMetrics
}

function global:Get-TSMetric {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$MetricLuid
    )

    return Get-TSObjects -Method GetMetric -Params @($MetricLuid)
}

#endregion METRICS
#region FAVORITES

function global:Get-TSFavorites+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers),
        [Parameter(Mandatory=$false)][object]$UsersWithFavorites,
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+),
        [Parameter(Mandatory=$false)][object]$Workbooks = (Get-TSWorkbooks+),
        [Parameter(Mandatory=$false)][object]$Views = (Get-TSViews+),
        [Parameter(Mandatory=$false)][object]$Datasources = (Get-TSDatsources+)
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $favoritesPlus = @()
    foreach ($user in ($UsersWithFavorites ?? $Users)) {
        $favorites = Get-TSObjects -Method GetFavorites -Params @($user.id) 
        foreach ($favorite in $favorites) {

            $favoriteType = $null

            if ($favorite.project) {$favoriteType = 'project'}
            if ($favorite.datasource) {$favoriteType = 'datasource'}
            if ($favorite.workbook) {$favoriteType = 'workbook'}
            if ($favorite.view) {$favoriteType = 'view'}

            if (!$favoriteType) {$favoriteType = "unknown"}

            $favoritePlus = [PSCustomObject]@{
                favoriteType = $favoriteType
                user = Find-TSUser -Users $Users -Id $user.id
                userId = $user.id 
                userName = $user.name
                ($favoriteType) = $null
                label = $favorite.label
                position = [int]$favorite.position
                addedat = [datetime]$favorite.addedat
            }

            $favoritePlusMembers = $favoritePlus | Get-Member -MemberType NoteProperty
            $favoriteMembers = $favorite | Get-Member -MemberType Property  | Where-Object {$_.name -notin $favoritePlusMembers.name}
            foreach ($member in  $favoriteMembers) {
                $favoritePlus.($member.Name) = $favorite.($member.Name)
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
                "unknown" {
                    $favoritePlus.PSObject.Properties.Remove("unknown")
                    $favoritePlus.favoriteType = $null
                }
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
        $response,$responseError = Add-TSFavorite -User $favorite.user -Label $favorite.label -Type $favorite.favoriteType -InputObject $favorite.($favorite.favoriteType)
        if ($responseError.code) {
            # $errorMessage = "Error adding favorite:  $($favorite.user.name)  $($favorite.label)  $($favorite.favoriteType)  $($favorite.($favorite.favoriteType).name)"
            # Write-Host+ $errorMessage -ForegroundColor Red
            # Write-Log -Message $errorMessage -EntryType "Error" -Action "AddFavorites" -Status "Error"
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
        [Parameter(Mandatory=$true)][Alias("Workbook","View","DataSource","Project")][object]$InputObject
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "AddFavorites" -Params @($User.id,($Label.replace("&","&amp;")),$Type,$InputObject.id)
    if ($responseError.code) {
        # $errorMessage = "Error $($responseError.code) ($($responseError.summary)): $($responseError.detail)"
        # Write-Host+ $errorMessage -ForegroundColor Red
        # Write-Log -Message $errorMessage -EntryType "Error" -Action "AddFavorites" -Status "Error"
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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $startTime = Get-Date -AsUTC
    $lastStartTime = (Read-Cache "AzureADSyncGroups").LastStartTime ?? [datetime]::MinValue

    $message = "Getting Azure AD groups and users"
    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor Gray

    $message = "  Group updates : PENDING"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

    $azureADGroupUpdates,$cacheError = Get-AzureADGroups -Tenant $Tenant -AsArray -After $lastStartTime
    if ($cacheError) {

        # Write-Log -Context "AzureADSyncTS" -Action ($Delta ? "Update" : "Get") -Target "Groups" -Status $cacheError.code -Message $cacheError.summary -EntryType "Error"
        # $message = "$($emptyString.PadLeft(8,"`b")) ERROR$($emptyString.PadLeft(8," "))"
        # Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor Red
        # $message = "    Error Code : $($($cacheError.code))"
        # Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,Red
        # $message = "    Error Summary : $($($cacheError.summary))"
        # Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,Red

        # Send-TaskMessage -Id "AzureADSyncTS" -Status $cacheError.code -Message $cacheError.summary -MessageType $PlatformMessageType.Alert

        return $cacheError

    }
    
    $message = "$($emptyString.PadLeft(8,"`b")) $($azureADGroupUpdates.Count)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen

    $message = "  Groups : PENDING"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

    $azureADGroups,$cacheError = Get-AzureADGroups -Tenant $Tenant -AsArray
    if ($cacheError) {

        # Write-Log -Context "AzureADSyncTS" -Action ($Delta ? "Update" : "Get") -Target "Groups" -Status $cacheError.code -Message $cacheError.summary -EntryType "Error"
        # $message = "$($emptyString.PadLeft(8,"`b")) ERROR$($emptyString.PadLeft(8," "))"
        # Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message -ForegroundColor Red
        # $message = "    Error Code : $($($cacheError.code))"
        # Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,Red
        # $message = "    Error Summary : $($($cacheError.summary))"
        # Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,Red

        # Send-TaskMessage -Id "AzureADSyncTS" -Status $cacheError.code -Message $cacheError.summary -MessageType $PlatformMessageType.Alert

        return $cacheError

    }

    # if ($azureADGroups.Count -le 0) {
    #     $message = "$($emptyString.PadLeft(8,"`b")) ($Delta ? 'SUCCESS' : 'CACHE EMPTY')$($emptyString.PadLeft(8," "))"
    #     Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message -ForegroundColor ($Delta ? "DarkGreen" : "Red")
    #     Write-Host+
    #     return
    # }

    $message = "$($emptyString.PadLeft(8,"`b")) $($azureADGroups.Count)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    
    $message = "  Users : PENDING"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

    $azureADUsers,$cacheError = Get-AzureADUsers -Tenant $Tenant -AsArray
    if ($cacheError) {

        # Write-Log -Context "AzureADSyncTS" -Action ($Delta ? "Update" : "Get") -Target "Users" -Status $cacheError.code -Message $cacheError.summary -EntryType "Error"
        # $message = "$($emptyString.PadLeft(8,"`b")) ERROR$($emptyString.PadLeft(8," "))"
        # Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor Red
        # $message = "    Error Code : $($($cacheError.code))"
        # Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,Red
        # $message = "    Error Summary : $($($cacheError.summary))"
        # Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,Red

        # Send-TaskMessage -Id "AzureADSyncTS" -Status $cacheError.code -Message $cacheError.summary -MessageType $PlatformMessageType.Alert

        return $cacheError

    }

    # if ($azureADUsers.Count -le 0) {
    #     $message = "$($emptyString.PadLeft(8,"`b")) ($Delta ? 'SUCCESS' : 'CACHE EMPTY')$($emptyString.PadLeft(8," "))"
    #     Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message -ForegroundColor ($Delta ? "DarkGreen" : "Red")
    #     Write-Host+
    #     return
    # }

    $message = "$($emptyString.PadLeft(8,"`b")) $($azureADUsers.Count)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

    Write-Host+
    $message = "Syncing Tableau Server groups : PENDING"
    Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

    foreach ($contentUrl in $global:AzureADSyncTS.Sites.ContentUrl) {

        Switch-TSSite $contentUrl
        $tsSite = Get-TSSite
        Write-Host+ -NoTrace "  Site: $($tsSite.name)"

        $tsGroups = Get-TSGroups | Where-Object {$_.name -in $azureADGroups.displayName -and $_.name -notin $global:tsRestApiConfig.SpecialGroups} | Select-Object -Property *, @{Name="site";Expression={$null}} | Sort-Object -Property name
        $tsUsers = Get-TSUsers | Sort-Object -Property name

        foreach ($tsGroup in $tsGroups) {

            Write-Host+ -NoTrace -NoNewLine "    Group: $($tsGroup.name)"

            $azureADGroupToSync = $azureADGroups | Where-Object {$_.displayName -eq $tsGroup.name}
            $tsGroupMembership = Get-TSGroupMembership -Group $tsGroup
            $azureADGroupMembership = $azureADUsers | Where-Object {$_.id -in $azureADGroupToSync.members -and $_.accountEnabled} | Foreach-Object {Update-AzureADUserEmail -Tenant $tenantKey -User $_} | Where-Object {![string]::IsNullOrEmpty($_.mail)}

            $tsUsersToAddToGroup = ($tsUsers | Where-Object {$_.name -in $azureADGroupMembership.userPrincipalName -and $_.id -notin $tsGroupMembership.id}) ?? @()
            $tsUsersToRemoveFromGroup = $tsGroupMembership | Where-object {$_.name -notin $azureADGroupMembership.userPrincipalName}

            $newUsers = @()
            $azureADUsersToAddToSite = $azureADGroupMembership | Where-Object {$_.userPrincipalName -notin $tsUsers.name} | Sort-Object -Property userPrincipalName
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

                $rebuildSearchIndex = Get-AsyncJob -Type RebuildSearchIndex | Where-Object {$_.status -eq "Created"}

                if ($rebuildSearchIndex) {
                    $rebuildSearchIndex = $rebuildSearchIndex[0]
                }
                else {
                    # force a reindex after creating users to ensure that group updates work
                    $rebuildSearchIndex = Invoke-TsmApiMethod -Method "RebuildSearchIndex"
                }

                $rebuildSearchIndex,$timeout = Wait-Asyncjob -id $rebuildSearchIndex.id -IntervalSeconds 5 -TimeoutSeconds 60
                if ($timeout) {
                    # Watch-AsyncJob -Id $rebuildSearchIndex.id -Callback "Write-AsyncJobStatusToLog" -NoMessaging
                }
                Write-AsyncJobStatusToLog -Id $rebuildSearchIndex.id

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

    $message = "Syncing Tableau Server groups : SUCCESS"
    Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGreen
    Write-Host+

}

function global:Sync-TSUsers {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [switch]$Delta
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $emptyString = ""
    $startTime = Get-Date -AsUTC

    $lastStartTime = (Read-Cache "AzureADSyncUsers").LastStartTime ?? [datetime]::MinValue

    $message = "Getting Azure AD users"
    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor Gray

    $message = "  User updates : PENDING"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

    $azureADUsers,$cacheError = Get-AzureADUsers -Tenant $Tenant -AsArray -After ($Delta ? $lastStartTime : [datetime]::MinValue)
    if ($cacheError) {
        Write-Log -Context "AzureADSyncTS" -Action ($Delta ? "Update" : "Get") -Target "Users" -Status $cacheError.code -Message $cacheError.summary -EntryType "Error"
        $message = "  $($emptyString.PadLeft(8,"`b")) ERROR$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,Red
        $message = "    Error $($cacheError.code) : $($($cacheError.summary))"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,Red
        return
    }

    $message = "$($emptyString.PadLeft(8,"`b")) $($azureADUsers.Count)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

    if ($azureADUsers.Count -le 0) {
        Write-Host+
        $message = "Syncing Tableau Server users : $($Delta ? 'SUCCESS' : 'CACHE EMPTY')"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,($Delta ? "DarkGreen" : "Red")
        Write-Host+
        return
    }

    Write-Host+
    $message = "Syncing Tableau Server users : PENDING"
    Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

    foreach ($contentUrl in $global:AzureADSyncTS.Sites.ContentUrl) {

        Switch-TSSite $contentUrl
        $tsSite = Get-TSSite

        Set-CursorInvisible

        $emptyString = ""

        $message = "    $($tssite.name) : PENDING"
        Write-Host+ -NoTrace -NoNewLine -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

        $tsUsers = Get-TSUsers | Where-Object {$_.name -in $azureADUsers.userPrincipalName -and $_.name -notin $global:tsRestApiConfig.SpecialAccounts} | Sort-Object -Property name

        Write-Host+ -NoTrace -NoTimeStamp "$($emptyString.PadLeft(8,"`b")) $($tsUsers.Count)$($emptyString.PadRight(7-$tsUsers.Count.ToString().Length)," ")" -ForegroundColor DarkGreen

        $lastOp = $null

        $tsUsers | Foreach-Object {

            $tsUser = Get-TSUser -Id $_.id
            $azureADUser = $azureADUsers | Where-Object {$_.userPrincipalName -eq $tsUser.name}
            $azureADUserAccountState = "AzureAD:$($azureADUser.accountEnabled ? "Enabled" : $(!$azureADUser ? "None" : "Disabled"))"
            Write-Host+ -NoTrace "      PROFILE: $($tsUser.id) $($tsUser.name) == $($tsUser.fullName ?? "null") | $($tsUser.email ?? "null") | $($tsUser.siteRole) | $($azureADUserAccountState)" -ForegroundColor DarkGray

            if ($lastOp -eq "NOOP") {
                Write-Host+ -NoTrace -NoNewLine -NoTimeStamp -Prefix "`r"
            }

            $fullName = $azureADUser.displayName ?? $tsUser.fullName
            $email = $azureADUser.mail ?? $tsUser.email

            if ($tsUser.siteRole -eq "Unlicensed" -and $azureADUser.accountEnabled) {
                $siteRole = $global:AzureADSyncTS.$($contentUrl).SiteRoleMinimum
            }
            else {
                $siteRole = $tsUser.siteRole
            }

            # if the users' Azure AD account has been disabled and they're not in an admin role, set them to unlicensed
            # ignore users that are already unlicensed
            # TODO: remove unlicensed users from their groups? 

            if ($tsUser.siteRole -notin $global:TSSiteAdminRoles -and !$azureADUser.accountEnabled) {

                if ($tsUser.SiteRole -ne "Unlicensed") {

                    $response, $responseError = Update-TSUser -User $tsUser -SiteRole "Unlicensed" | Out-Null
                    if ($responseError) {
                        Write-Log -Context "AzureADSyncTS" -Action "DisableUser" -Target "$($tsSite.contentUrl)\$($tsUser.name)" -Message "$($responseError.detail)" -EntryType "Error"
                        Write-Host+ "      $($response.error.detail)" -ForegroundColor Red
                    }
                    else {
                        # Write-Log -Context "AzureADSyncTS" -Action "DisableUser" -Target "$($tsSite.contentUrl)\$($tsUser.name)" -Message "$siteRole" -EntryType "Information" -Force
                        Write-Host+ -NoTrace "      Disable: $($tsUser.id) $($tsUser.name): $($tsUser.siteRole) >> $siteRole" -ForegroundColor Red
                    }

                    $lastOp = "Disable"

                }

            }
            
            # Update-tsUser replaces both apostrophe characters ("'" and "’") in fullName and email with "&apos;" (which translates to "'")
            # Replace "’" with "'" in order to correctly compare fullName and email from $tsUser and $azureADUser 
            
            elseif ($fullName.replace("’","'") -ne $tsUser.fullName -or $email.replace("’","'") -ne $tsUser.email -or $siteRole -ne $tsUser.siteRole) {
                $response, $responseError = Update-tsUser -User $tsUser -FullName $fullName -Email $email -SiteRole $siteRole | Out-Null
                if ($responseError) {
                    Write-Log -Context "AzureADSyncTS" -Action "UpdateUser" -Target "$($tsSite.contentUrl)\$($tsUser.name)" -Message "$($responseError.detail)" -EntryType "Error"
                    Write-Host+ "      $($response.error.detail)" -ForegroundColor Red
                }
                else {
                    # Write-Log -Context "AzureADSyncTS" -Action "UpdateUser" -Target "$($tsSite.contentUrl)\$($tsUser.name)" -Message "$fullName | $email | $siteRole" -EntryType "Information" -Force
                    # Write-Host+ -NoTrace "      Update: $($tsUser.id) $($tsUser.name) == $($tsUser.fullName ?? "null") | $($tsUser.email ?? "null") | $($tsUser.siteRole)" -ForegroundColor DarkYellow
                    Write-Host+ -NoTrace "      Update: $($tsUser.id) $($tsUser.name) << $fullName | $email | $siteRole" -ForegroundColor DarkGreen
                }
                
                $lastOp = "Update"
            }
            else {
                # # no update
                # Write-Host+ -NoTrace "    NOOP: $($tsUser.id) $($tsUser.name)" -ForegroundColor DarkGray
                $lastOp = "NOOP"
            }
        
        }

    }

    @{LastStartTime = $startTime} | Write-Cache "AzureADSyncUsers"

    $message = "  Syncing Tableau Server users : SUCCESS"
    Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGreen
    
    Write-Host+

}

#endregion SYNC
#region MISC
function global:Get-TSUsersDistributionLists {

[CmdletBinding()]
param(
    [switch]$ExcludePATHUsers,
    [switch]$ActiveOnly
)

$users = @()
$sites = Get-TSSites
foreach ($site in $sites) {
    Switch-TSSite -Site $site.contentUrl
    $siteUsers = Get-TSUsers | Where-Object {$_.siteRole -ne "Unlicensed"} 
    if ($ExcludePATHUsers) {
        $siteUsers = $siteUsers | Where-Object {$_.name -notlike "*@path.org"}
    }
    foreach ($siteUser in $siteUsers) {
        $user = Get-TSUser -Id $siteUser.Id
        if ($ActiveOnly) {
            if ($user.lastLogin -and ((Get-Date -AsUTC)-[datetime]($user.lastLogin)).TotalDays -le 90) {
                $users += $user
            }
        }
        else {
            $users += $user
        }
        
    }
}

$emailAddresses = @()
foreach ($user in $users) {
    $emailAddresses += $user.email ?? $user.name
}
$emailAddresses = $emailAddresses | Sort-Object -Unique

$distributionLists = @()
$distributionLists += $emailAddresses[0..249] -join "; "
$distributionLists += $emailAddresses[250..499] -join "; "
$distributionLists += $emailAddresses[500..749] -join "; "
$distributionLists += $emailAddresses[750..999] -join "; "

return $users, $emailAddresses, $distributionLists

}

#endregion MISC