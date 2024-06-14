class TSRestApiResponseError {

    [string]$Code
    [string]$Summary
    [string]$Detail
    [string]$Message

    TSRestApiResponseError([object]$ResponseError) { $this.Init($ResponseError) }

    [void]Init([object]$ResponseError) {

        switch ($this.EndpointVersioningType) {
            "PerResourceVersioning" {
                $this.Message = "$($ResponseError.Code) ($($ResponseError.Summary)): $($ResponseError.Detail)"
            }
            default {
                $this.Message = $ResponseError
            }
        }

    }

}

class TSRestApiResponse {

    [string]$Root 
    [string]$Keys

    TSRestApiResponse() { $this.Init() }

    [void]Init() {

        switch ($this.EndpointVersioningType) {
            "PerResourceVersioning" {
                $this.Root = ""
            }
            default {
                $this.Root = "tsResponse"
            }
        }

    }

}


class TSRestApiMethodPrerequisite {

    [string[]]$Platform
    [object]$ApiVersion

    TSRestApiMethodPrerequisite() { $this.Init() }

    [void]Init() {}

    [void]Validate() {

        if ($this.ApiVersion) {
            if ($this.EndpointVersioningType -eq "RestApiVersioning") {
                if (![string]::IsNullOrEmpty($this.ApiVersion.Minimum) -or ![string]::IsNullOrEmpty($this.ApiVersion.Maximum)) {
                    $_apiVersion = $global:tsRestApiConfig.RestApiVersioning.ApiVersion
                    if ((![string]::IsNullOrEmpty($this.ApiVersion.Minimum) -and $_apiVersion -lt $this.ApiVersion.Minimum) -or
                        (![string]::IsNullOrEmpty($this.ApiVersion.Maximum) -and $_apiVersion -gt $this.ApiVersion.Maximum))
                    {
                        throw "Method `"($this.Name)`" is not supported for Tableau Server REST API $($this.ApiVersion.Minimum)."
                    }
                }
            }
        }

        if (![string]::IsNullOrEmpty($this.Platform)) {
            if ($this.Platform -notcontains $global:tsRestApiConfig.Platform.Id) {
                throw "Method `"($this.Name)`" is not supported for $($global:tsRestApiConfig.Platform.Name)"
            }
        }
    }

}

class TSRestApiMethod {

    [string]$Name
    [string]$Endpoint
    [ValidateSet("GET","PUT","POST","DELETE")][string]$HttpMethod 
    [string]$Body 
    [TSRestApiResponse]$Response 
    [ValidateSet("RestApiVersioning","PerResourceVersioning")][string]$EndpointVersioningType 
    [string]$Revision
    [string]$ResourceString
    [TSRestApiMethodPrerequisite]$Prerequisite

    TSRestApiMethod() { $this.Init() }

    [void]Init() {
        if ([string]::IsNullOrEmpty($this.EndpointVersioningType)) {
            $this.EndpointVersioningType = ![string]::IsNullOrEmpty($this.ResourceString) ? "PerResourceVersioning" : "RestApiVersioning"
        }
    }
    
    [uri]Uri() {

        $_server = $global:tsRestApiConfig.Server
        $_apiVersion = ""
        switch ($this.EndpointVersioningType) {
            "PerResourceVersioning" {
                $_apiVersion = "-"
            }
            default {
                $_apiVersion = $global:tsRestApiConfig.RestApiVersioning.ApiVersion
            }
        }

        return "https://$_server/api/$_apiVersion/$($this.Endpoint)"
        
    }

}

function global:Initialize-TSRestApiConfiguration {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Server = $global:Platform.Uri.Host,
        [Parameter(Mandatory=$false)][Alias("Site")][string]$ContentUrl = "",
        [Parameter(Mandatory=$false)][string]$Credentials = "localadmin-$($global:Platform.Instance)",
        [switch]$Reset
    )

    $prerequisiteTestResults = Test-Prerequisites -Type "Provider" -Id "TableauServerRestApi" -ComputerName $Server -Quiet
    if (!$prerequisiteTestResults.Pass) { 
        throw $prerequisiteTestResults.Prerequisites[0].Tests.Reason
    }

    if ($Reset) {
        $global:tsRestApiConfig = @{}
    }

    $_provider = Get-Provider -Id "TableauServerRestApi"

    $global:tsRestApiConfig = @{
        Server = $Server
        Credentials = Get-Credentials $Credentials
        Token = $null
        SiteId = $null
        ContentUrl = $ContentUrl
        UserId = $null
        SpecialAccounts = @("guest","tableausvc","TabSrvAdmin","alteryxsvc")
        SpecialGroups = @("All Users")
        SpecialMethods = @("ServerInfo","Login")
        Defaults = $_provider.Config.Defaults
    }

    $global:tsRestApiConfig.RestApiVersioning = @{
        ApiUri = ""
        ApiVersion = $global:Catalog.Provider.TableauServerRestApi.Initialization.Api.Version.Minimum
        ContentType = "application/xml; charset=utf-8"
        Headers = @{
            "Accept" = "*/*"
            "X-Tableau-Auth" = $global:tsRestApiConfig.Token
        }
    }
    $global:tsRestApiConfig.RestApiVersioning.ApiUri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)"
    $global:tsRestApiConfig.RestApiVersioning.Headers."Content-Type" = $global:tsRestApiConfig.RestApiVersioning.ContentType

    $global:tsRestApiConfig.PerResourceVersioning = @{
        ApiUri = "https://$($global:tsRestApiConfig.Server)/api/-"
        ContentType = "application/vnd.<ResourceString>+json; charset=utf-8"
        Headers = @{
            "Accept" = "*/*"
            "X-Tableau-Auth" = $global:tsRestApiConfig.Token
        }
    }
    $global:tsRestApiConfig.PerResourceVersioning.Headers."Content-Type" = $global:tsRestApiConfig.PerResourceVersioning.ContentType
    
    $global:tsRestApiConfig.Method = @{
        Login = [TSRestApiMethod]@{
            Name = "Login"
            Endpoint ="auth/signin"
            HttpMethod = "POST"
            Body = "<tsRequest><credentials name='<0>' password='<1>'><site contentUrl='<2>'/></credentials></tsRequest>"
            Response = @{Keys = "credentials"} 
        } 
        ServerInfo = [TSRestApiMethod]@{
            Name = "ServerInfo"
            Endpoint ="serverinfo"
            HttpMethod = "GET"
            Response = @{Keys = "serverinfo"}
        }
    }

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method Login -Params @($global:tsRestApiConfig.Credentials.UserName,$global:tsRestApiConfig.Credentials.GetNetworkCredential().Password,$global:tsRestApiConfig.ContentUrl)
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

    if ($global:Catalog.Provider.TableauServerRestApi.Initialization.Api.Version.AutoUpdate) {
        $global:tsRestApiConfig.RestApiVersioning.ApiVersion = $serverinfo.restApiVersion
        $global:tsRestApiConfig.PerResourceVersioning.ApiVersion = $serverinfo.restApiVersion
    }

    if ($Server -eq "localhost" -or $Server -eq $env:COMPUTERNAME -or $Server -eq $global:Platform.Uri.Host) {
        $global:tsRestApiConfig.Platform = $global:Platform
    }
    else {
        $_type = $global:tsRestApiConfig.Platform.Id ?? ($Server -match "online\.tableau\.com$" ? "TableauCloud" : "TableauServer")
        $global:tsRestApiConfig.Platform = $global:Catalog.Platform.$_type | Copy-Object
        $global:tsRestApiConfig.Platform.Uri = [System.Uri]::new("https://$Server")
        $global:tsRestApiConfig.Platform.Domain = $Server.Split(".")[-1]
        $global:tsRestApiConfig.Platform.Instance = "$($Server.Replace(".","-"))"
    }

    $global:tsRestApiConfig.Platform.Version = $serverinfo.productVersion.InnerText
    $global:tsRestApiConfig.Platform.Build = $serverinfo.productVersion.build
    $global:tsRestApiConfig.Platform.DisplayName = $global:tsRestApiConfig.Platform.Name + " " + $global:tsRestApiConfig.Platform.Version

    $platformInfo = @{
        Version=$global:Platform.Version
        Build=$global:Platform.Build
        # TsRestApiVersion=$global:Platform.Api.TsRestApiVersion
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

            Login = [TSRestApiMethod]@{
                Name = "Login"
                Endpoint ="auth/signin"
                HttpMethod = "POST"
                Body = "<tsRequest><credentials name='<0>' password='<1>'><site contentUrl='<2>'/></credentials></tsRequest>"
                Response = @{Keys = "credentials"}
            } 
            GetCurrentSession = [TSRestApiMethod]@{
                Name = "GetCurrentSession"
                Endpoint ="sessions/current"
                HttpMethod = "GET"
                Response = @{Keys = "session"}
            }
            Logout = [TSRestApiMethod]@{
                Name = "Logout"
                Endpoint ="auth/signout"
                HttpMethod = "POST"
            }

        #endregion SESSION METHODS
        #region SERVER METHODS

            ServerInfo = [TSRestApiMethod]@{
                Name = "ServerInfo"
                Endpoint ="serverinfo"
                HttpMethod = "GET"
                Response = @{Keys = "serverinfo"}
            }
            GetDomains = [TSRestApiMethod]@{
                Name = "GetDomains"
                Endpoint ="domains"
                HttpMethod = "GET"
                Response = @{Keys = "domainList"}
            }

        #endregion SERVER METHODS
        #region GROUP METHODS

            GetGroups = [TSRestApiMethod]@{
                Name = "GetGroups"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/groups"
                HttpMethod = "GET"
                Response = @{Keys = "groups.group"}
            }
            AddGroupToSite = [TSRestApiMethod]@{
                Name = "AddGroupToSite"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/groups"
                HttpMethod = "POST"
                Body = "<tsRequest><group name='<0>'/></tsRequest>"
                Response = @{Keys = "group"}
            }
            RemoveGroupFromSite = [TSRestApiMethod]@{
                Name = "RemoveGroupFromSite"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/groups/<0>"
                HttpMethod = "DELETE"
                Response = @{Keys = "group"}
            }
            GetGroupMembership = [TSRestApiMethod]@{
                Name = "GetGroupMembership"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/groups/<0>/users"
                HttpMethod = "GET"
                Response = @{Keys = "users.user"}
            }
            AddUserToGroup = [TSRestApiMethod]@{
                Name = "AddUserToGroup"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/groups/<0>/users"
                HttpMethod = "POST"
                Body = "<tsRequest><user id='<1>'/></tsRequest>"
                Response = @{Keys = "user"}
            }
            RemoveUserFromGroup = [TSRestApiMethod]@{
                Name = "RemoveUserFromGroup"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/groups/<0>/users/<1>"
                HttpMethod = "DELETE"
                Response = @{Keys = ""}
            }

        #endregion GROUP METHODS
        #region SITE METHODS

            SwitchSite = [TSRestApiMethod]@{
                Name = "SwitchSite"
                Endpoint ="auth/switchSite"
                HttpMethod = "POST"
                Body = "<tsRequest><site contentUrl='<0>'/></tsRequest>"
                Response = @{Keys = "credentials"}
            } 
            GetSites = [TSRestApiMethod]@{
                Name = "GetSites"
                Endpoint ="sites"
                HttpMethod = "GET"
                Response = @{Keys = "sites.site"}
            }
            GetSite = [TSRestApiMethod]@{
                Name = "GetSite"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)"
                HttpMethod = "GET"
                Response = @{Keys = "site"}
            }

        #endregion SITE METHODS
        #region USER METHODS

            GetUsers = [TSRestApiMethod]@{
                Name = "GetUsers"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/users?fields=_all_"
                HttpMethod = "GET"
                Response = @{Keys = "users.user"}
            }
            GetUser = [TSRestApiMethod]@{
                Name = "GetUser"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/users/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "user"}
            }
            AddUser = [TSRestApiMethod]@{
                Name = "AddUser"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/users"
                HttpMethod = "POST"
                Body = "<tsRequest><user name='<0>' siteRole='<1>' /></tsRequest>"
                Response = @{Keys = "user"}
            }
            RemoveUser = [TSRestApiMethod]@{
                Name = "RemoveUser"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/users/<0>"
                HttpMethod = "DELETE"
                Response = @{Keys = ""}
            }
            UpdateUser = [TSRestApiMethod]@{
                Name = "UpdateUser"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/users/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><user fullName=`"<1>`" email=`"<2>`" siteRole=`"<3>`" /></tsRequest>"
                Response = @{Keys = "user"}
            }
            UpdateUserPassword = [TSRestApiMethod]@{
                Name = "UpdateUserPassword"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/users/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><user password='<1>' /></tsRequest>"
                Response = @{Keys = "user"}
            }
            GetUserMembership = [TSRestApiMethod]@{
                Name = "GetUserMembership"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/users/<0>/groups"
                HttpMethod = "GET"
                Response = @{Keys = "groups.group"}
            }

        #endregion USER METHODS
        #region PROJECT METHODS 
            
            GetProjects = [TSRestApiMethod]@{
                Name = "GetProjects"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/projects"
                HttpMethod = "GET"
                Response = @{Keys = "projects.project"}
            }
            GetProjectPermissions = [TSRestApiMethod]@{
                Name = "GetProjectPermissions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }
            GetProjectDefaultPermissions = [TSRestApiMethod]@{
                Name = "GetProjectDefaultPermissions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/default-permissions/<1>"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }
            AddProjectPermissions = [TSRestApiMethod]@{
                Name = "AddProjectPermissions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }
            AddProjectDefaultPermissions = [TSRestApiMethod]@{
                Name = "AddProjectDefaultPermissions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/default-permissions/<1>"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><2></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }
            RemoveProjectPermissions = [TSRestApiMethod]@{
                Name = "RemoveProjectPermissions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/permissions/<1>/<2>/<3>/<4>"
                HttpMethod = "DELETE"
                Response = @{Keys = "permissions"}
            }
            RemoveProjectDefaultPermissions = [TSRestApiMethod]@{
                Name = "RemoveProjectDefaultPermissions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/default-permissions/<1>/<2>/<3>/<4>/<5>"
                HttpMethod = "DELETE"
                Response = @{Keys = "permissions"}
            }

        #endregion PROJECT METHODS
        #region WORKBOOK METHODS

            GetWorkbooks = [TSRestApiMethod]@{
                Name = "GetWorkbooks"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/workbooks"
                HttpMethod = "GET"
                Response = @{Keys = "workbooks.workbook"}
            }
            GetWorkbook = [TSRestApiMethod]@{
                Name = "GetWorkbook"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "workbook"}
            }
            UpdateWorkbook = [TSRestApiMethod]@{
                Name = "UpdateWorkbook"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><workbook name='<1>' ><project id='<2>' /><owner id='<3>' /></workbook></tsRequest>"
                Response = @{Keys = "workbook"}
            }
            GetWorkbookConnections = [TSRestApiMethod]@{
                Name = "GetWorkbookConnections"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/connections"
                HttpMethod = "GET"
                Response = @{Keys = "connections.connection"}
            }
            GetWorkbookRevisions = [TSRestApiMethod]@{
                Name = "GetWorkbookRevisions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/revisions"
                HttpMethod = "GET"
                Response = @{Keys = "revisions.revision"}
            }
            GetWorkbookRevision = [TSRestApiMethod]@{
                Name = "GetWorkbookRevision"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/revisions/<1>"
                HttpMethod = "GET"
                Response = @{Keys = "revisions.revision"}
                Revision = "<1>"
            }
            GetWorkbookPermissions = [TSRestApiMethod]@{
                Name = "GetWorkbookPermissions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }   
            AddWorkbookPermissions = [TSRestApiMethod]@{
                Name = "AddWorkbookPermissions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }

        #endregion WORKBOOK METHODS
        #region VIEW METHODS 

            GetView = [TSRestApiMethod]@{
                Name = "GetView"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/views/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "view"}
            }
            GetViewsForSite = [TSRestApiMethod]@{
                Name = "GetViewsForSite"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/views"
                HttpMethod = "GET"
                Response = @{Keys = "views.view"}
            }
            GetViewsForWorkbook = [TSRestApiMethod]@{
                Name = "GetViewsForWorkbook"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/views"
                HttpMethod = "GET"
                Response = @{Keys = "views.view"}
            }
            GetViewPermissions = [TSRestApiMethod]@{
                Name = "GetViewPermissions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/views/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }   
            AddViewPermissions = [TSRestApiMethod]@{
                Name = "AddViewPermissions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/views/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }

        #endregion VIEW METHODS 
        #region CUSTOMVIEW METHODS 

            GetCustomView = [TSRestApiMethod]@{
                Name = "GetCustomView"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/customviews/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "customview"}
                Prerequisite = @{ 
                    Platform = "TableauCloud"
                    ApiVersion = @{
                        Minimum = "3.18" 
                    }
                }
            }
            GetCustomViewsForSite = [TSRestApiMethod]@{
                Name = "GetCustomViewsForSite"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/customviews"
                HttpMethod = "GET"
                Response = @{Keys = "customviews.customview"}
                Prerequisite = @{ 
                    Platform = "TableauCloud"
                    ApiVersion = @{
                        Minimum = "3.18" 
                    }
                }
            }

        #endregion VIEW METHODS         
        #region DATASOURCE METHODS 

            GetDatasource = [TSRestApiMethod]@{
                Name = "GetDatasource"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "datasource"}
            }
            GetDatasources = [TSRestApiMethod]@{
                Name = "GetDatasources"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/datasources"
                HttpMethod = "GET"
                Response = @{Keys = "datasources.datasource"}
            }
            UpdateDatasource = [TSRestApiMethod]@{
                Name = "UpdateDatasource"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><datasource name='<1>' ><project id='<2>' /><owner id='<3>' /></datasource></tsRequest>"
                Response = @{Keys = "datasource"}
            }
            GetDatasourcePermissions = [TSRestApiMethod]@{
                Name = "GetDatasourcePermissions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }
            AddDatasourcePermissions = [TSRestApiMethod]@{
                Name = "AddDatasourcePermissions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }
            GetDatasourceRevisions = [TSRestApiMethod]@{
                Name = "GetDatasourceRevisions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>/revisions"
                HttpMethod = "GET"
                Response = @{Keys = "revisions.revision"}
            }
            GetDatasourceRevision = [TSRestApiMethod]@{
                Name = "GetDatasourceRevision"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>/revisions/<1>"
                HttpMethod = "GET"
                Response = @{Keys = "revisions.revision"}
                Revision = "<1>"
            }
            GetDatasourceConnections = [TSRestApiMethod]@{
                Name = "GetDatasourceConnections"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>/connections"
                HttpMethod = "GET"
                Response = @{Keys = "connections.connection"}
            }

        #endregion DATASOURCE METHODS
        #region FLOW METHODS

            GetFlows = [TSRestApiMethod]@{
                Name = "GetFlows"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/flows"
                HttpMethod = "GET"
                Response = @{Keys = "flows.flow"}
            }
            GetFlowsForUser = [TSRestApiMethod]@{
                Name = "GetFlowsForUser"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/<0>/flows"
                HttpMethod = "GET"
                Response = @{Keys = "flows.flow"}
            }
            GetFlow = [TSRestApiMethod]@{
                Name = "GetFlow"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/flows/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "flow"}
            }
            UpdateFlow = [TSRestApiMethod]@{
                Name = "UpdateFlow"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/flows/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><flow name='<1>' ><project id='<2>' /><owner id='<3>' /></flow></tsRequest>"
                Response = @{Keys = "flow"}
            }
            GetFlowPermissions = [TSRestApiMethod]@{
                Name = "GetFlowPermissions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/flows/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }
            AddFlowPermissions = [TSRestApiMethod]@{
                Name = "AddFlowPermissions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/flows/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }
            GetFlowConnections = [TSRestApiMethod]@{
                Name = "GetFlowConnections"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/flows/<0>/connections"
                HttpMethod = "GET"
                Response = @{Keys = "connections.connection"}
            }
            GetFlowRevisions = [TSRestApiMethod]@{
                Name = "GetFlowRevisions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/flows/<0>/revisions"
                HttpMethod = "GET"
                Response = @{Keys = "revisions.revision"}
            }
            GetFlowRevision = [TSRestApiMethod]@{
                Name = "GetFlowRevision"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/flows/<0>/revisions/<1>"
                HttpMethod = "GET"
                Response = @{Keys = "revisions.revision"}
                Revision = "<1>"
            }

        #endregion FLOW METHODS          
        #region METRIC METHODS

            GetMetrics = [TSRestApiMethod]@{
                Name = "GetMetrics"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/metrics"
                HttpMethod = "GET"
                Response = @{Keys = "metrics.metric"}
            }
            GetMetric = [TSRestApiMethod]@{
                Name = "GetMetric"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/metrics/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "metrics.metric"}
            }
            UpdateMetric = [TSRestApiMethod]@{
                Name = "UpdateMetric"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/metrics/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><metric name='<1>' ><project id='<2>' /><owner id='<3>' /></metric></tsRequest>"
                Response = @{Keys = "metric"}
            }

        #endregion METRIC METHODS
        #region COLLECTION METHODS

            GetCollections = [TSRestApiMethod]@{
                Name = "GetCollections"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/collections/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "collections.collection"}
                Prerequisite =  @{
                    ApiVersion = @{
                        Minimum = "9.99"
                    }
                }
            }

        #endregion COLLECTION METHODS
        #region VIRTUALCONNECTION METHODS

            GetVirtualConnections = [TSRestApiMethod]@{
                Name = "GetVirtualConnections"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/virtualconnections"
                HttpMethod = "GET"
                Response = @{Keys = "virtualconnections.virtualconnection"}
                Prerequisite = @{ 
                    Platform = "TableauCloud"
                    ApiVersion = @{
                        Minimum = "3.18" 
                    }
                }
            }

        #endregion VIRTUALCONNECTION METHODS
        #region FAVORITE METHODS

            GetFavorites = [TSRestApiMethod]@{
                Name = "GetFavorites"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/favorites/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "favorites.favorite"}
            }
            AddFavorite = [TSRestApiMethod]@{
                Name = "AddFavorite"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/favorites/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><favorite label='<1>'><<2> id='<3>'/></favorite></tsRequest>"
                Response = @{Keys = "favorites.favorite"}
            }
            RemoveFavorite = [TSRestApiMethod]@{
                Name = "RemoveFavorite"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/favorites/<0>/<1>/<2>"
                HttpMethod = "DELETE"
                Response = @{Keys = "favorites.favorite"}
            }

        #endregion FAVORITE METHODS
        #region SCHEDULES

            GetSchedules = [TSRestApiMethod]@{
                Name = "GetSchedules"
                Endpoint ="schedules"
                HttpMethod = "GET"
                Response = @{Keys = "schedules.schedule"}
            }
            GetSchedule = [TSRestApiMethod]@{
                Name = "GetSchedule"
                Endpoint ="schedules/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "schedule"}
            }
        
        #endregion SCHEDULES
        #region SUBSCRIPTIONS

            GetSubscriptions = [TSRestApiMethod]@{
                Name = "GetSubscriptions"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/subscriptions"
                HttpMethod = "GET"
                Response = @{Keys = "subscriptions.subscription"}
            }
            GetSubscription = [TSRestApiMethod]@{
                Name = "GetSubscription"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/subscriptions/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "subscription"}
            }

        #endregion SUBSCRIPTIONS
        #region NOTIFICATIONS
            
            GetDataAlerts = [TSRestApiMethod]@{
                Name = "GetDataAlerts"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/dataAlerts"
                HttpMethod = "GET"
                Response = @{Keys = "dataAlerts.dataAlert"}
            }
            GetWebhooks = [TSRestApiMethod]@{
                Name = "GetWebhooks"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/webhooks"
                HttpMethod = "GET"
                Response = @{Keys = "webhooks.webhook"}
            }
            GetWebhook = [TSRestApiMethod]@{
                Name = "GetWebhook"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/webhooks/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "webhook"}
            }
            GetUserNotificationPreferences = [TSRestApiMethod]@{
                Name = "GetUserNotificationPreferences"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/settings/notifications"
                HttpMethod = "GET"
                Response = @{Keys = "userNotificationsPreferences.userNotificationsPreference"}
            }

        #endregion NOTIFICATIONS
        #region ANALYTICS EXTENSIONS

            GetAnalyticsExtensionsConnectionsForSite = [TSRestApiMethod]@{
                Name = "GetAnalyticsExtensionsConnectionsForSite"
                Endpoint ="settings/site/extensions/analytics/connections"
                HttpMethod = "GET"
                Response = @{Keys = "connectionList"}
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
            }
            GetAnalyticsExtensionsEnabledStateForSite = [TSRestApiMethod]@{
                Name = "GetAnalyticsExtensionsEnabledStateForSite"
                Endpoint ="settings/site/extensions/analytics"
                HttpMethod = "GET"
                Response = @{Keys = "enabled"}
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
            }  

        #endregion ANALYTICS EXTENSIONS
        #region DASHBOARD EXTENSIONS

            GetDashboardExtensionSettingsForServer = [TSRestApiMethod]@{
                Name = "GetDashboardExtensionSettingsForServer"
                Endpoint ="settings/server/extensions/dashboard"
                HttpMethod = "GET"
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
            } 
            GetBlockedDashboardExtensionsForServer = [TSRestApiMethod]@{
                Name = "GetBlockedDashboardExtensionsForServer"
                Endpoint ="settings/server/extensions/dashboard/blockListItems"
                HttpMethod = "GET"
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
            }  
            GetDashboardExtensionSettingsForSite = [TSRestApiMethod]@{
                Name = "GetDashboardExtensionSettingsForSite"
                Endpoint ="settings/site/extensions/dashboard"
                HttpMethod = "GET"
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
            } 
            GetAllowedDashboardExtensionsForSite = [TSRestApiMethod]@{
                Name = "GetAllowedDashboardExtensionsForSite"
                Endpoint ="settings/site/extensions/dashboard/safeListItems"
                HttpMethod = "GET"
                ResourceString = "tableau.analyticsextensions.v1.ConnectionMetadataList"
            }

        #endregion DASHBOARD EXTENSIONS
        #region CONNECTED APPLICATIONS

            GetConnectedApplications = [TSRestApiMethod]@{
                Name = "GetConnectedApplications"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/connected-applications"
                HttpMethod = "GET"
                Response = @{Keys = "connectedApplications.connectedApplication"}
            }
            GetConnectedApplication = [TSRestApiMethod]@{
                Name = "GetConnectedApplication"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/connected-applications/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "connectedApplications.connectedApplication"}
            }

        #endregion CONNECTED APPLICATIONS
        #region PUBLISH

            PublishWorkbook = [TSRestApiMethod]@{
                Name = "PublishWorkbook"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/workbooks?overwrite=true"
                HttpMethod = "POST"
                Response = @{Keys = "workbook"}
            }
            PublishDatasource = [TSRestApiMethod]@{
                Name = "PublishDatasource"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/datasources?overwrite=true"
                HttpMethod = "POST"
                Response = @{Keys = "datasource"}
            }
            InitiateFileUpload = [TSRestApiMethod]@{
                Name = "InitiateFileUpload"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/fileUploads/"
                HttpMethod = "POST"
                Response = @{Keys = "fileUpload.uploadSessionId"}
            }
            AppendToFileUpload = [TSRestApiMethod]@{
                Name = "AppendToFileUpload"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/fileUploads/<0>"
                HttpMethod = "PUT"
                Response = @{Keys = "fileUpload"}
            }
            PublishWorkbookMultipart = [TSRestApiMethod]@{
                Name = "PublishWorkbookMultipart"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/workbooks?uploadSessionId=<0>&workbookType=<1>&overwrite=<2>"
                HttpMethod = "POST"
                Response = @{Keys = "workbook"}
            }
            PublishDatasourceMultipart = [TSRestApiMethod]@{
                Name = "PublishDatasourceMultipart"
                Endpoint ="sites/$($global:tsRestApiConfig.SiteId)/datasources?uploadSessionId=<0>&datasourceType=<1>&overwrite=<2>"
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

    # if not the ServerInfo or Login methods AND the token is null, login
    if ($Method -notin $global:tsRestApiConfig.SpecialMethods -and !$global:tsRestApiConfig.Token) {

        $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method Login -Params @($global:tsRestApiConfig.Credentials.UserName,$global:tsRestApiConfig.Credentials.GetNetworkCredential().Password,$global:tsRestApiConfig.ContentUrl)
        if (!$responseError) {
            $global:tsRestApiConfig.Token = $response.token
            $global:tsRestApiConfig.SiteId = $response.site.id
            $global:tsRestApiConfig.ContentUrl = $response.site.contentUrl
            $global:tsRestApiConfig.UserId = $response.user.id 
            $global:tsRestApiConfig.$($global:TsRestApiConfig.Method.$Method.EndpointVersioningType).Headers."X-Tableau-Auth" = $global:tsRestApiConfig.Token
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

    # check method's prerequisites
    try {
        if ($global:tsRestApiConfig.Method.$Method.Prerequisite) {
            $global:tsRestApiConfig.Method.$Method.Prerequisite.Validate()
        }
    }
    catch {
        Write-Host+ $_.Exception.Message -Foreground Red
        return
    }
    
    $responseRoot = $global:tsRestApiConfig.Method.$Method.Response.Root
    
    $pageFilter = "pageNumber=$($PageNumber)&pageSize=$($PageSize)"
    $_filter = $Filter ? "filter=$($Filter)&$($pageFilter)" : "$($pageFilter)"

    $httpMethod = $global:tsRestApiConfig.Method.$Method.HttpMethod

    $uri = "$($global:tsRestApiConfig.Method.$Method.Uri())"
    $questionMarkOrAmpersand = $uri.Contains("?") ? "&" : "?"
    $uri += ($global:tsRestApiConfig.Method.$Method.EndpointVersioningType -Eq "RestApiVersioning") -and $httpMethod -eq "GET" ? "$($questionMarkOrAmpersand)$($_filter)" : $null

    $body = $global:tsRestApiConfig.Method.$Method.Body

    $headers = $global:tsRestApiConfig.$($global:tsRestApiConfig.Method.$Method.EndpointVersioningType).Headers | Copy-Object
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
        $response = Invoke-RestMethod -Uri $uri -Method $httpMethod -Headers $headers -Body $body -ContentType $global:tsRestApiConfig.$($global:TsRestApiConfig.Method.$Method.EndpointVersioningType).ContentType -TimeoutSec $TimeoutSec -ResponseHeadersVariable responseHeaders
        if ($global:tsRestApiConfig.Method.$Method.EndpointVersioningType -Eq "RestApiVersioning") {
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
        # not sure why the Tableau Server REST API error messages aren't formatted correctly: fix it
        if ($_.ErrorDetails.Message -cmatch "^.*([a-z])([A-Z]).*$") {
            $responseError = $matches[0] -replace "$($matches[1])$($matches[2])","$($matches[1]): $($matches[2])"
        }
        $responseError = $responseError ?? $_.Exception.Message
    }

    if ($responseError) {

        # if this is because the token has expired, then set the token to null and reinvoke the call
        # nullifying the token forces a login before completing the original call
        # after reinvoking the call, the original call must return from here or it will loop
        if ($responseError.StartsWith("Unauthorized Access")) {
            $global:tsRestApiConfig.Token = $null
            $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method $Method -Params $Params -PageNumber $PageNumber -PageSize $PageSize -Filter $Filter -TimeoutSec $TimeoutSec
            return $response, $pagination, $responseError
        }

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
        [Parameter(Mandatory=$true)][Alias("Workbook","View","Datasource","Flow","Metric","Collection","VirtualConnection")][object]$InputObject,
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

    $responseRoot = $global:tsRestApiConfig.Method.$Method.Response.Root

    $objectType = $global:tsRestApiConfig.Method.$Method.Response.Keys.Split(".")[-1]

    $projectPath = ""
    $projects = Get-TSProjects
    $project = $projects | Where-Object {$_.id -eq $InputObject.project.id}
    do {
        $projectName = [System.Web.HttpUtility]::UrlEncode($project.Name)
        $projectPath = $projectName + ($projectPath ? "\" : $null) + $projectPath
        $project = $projects | Where-Object {$_.id -eq $project.parentProjectId}
    } until (!$project)

    $contentUrl = ![string]::IsNullOrEmpty($global:tsRestApiConfig.ContentUrl) ? $global:tsRestApiConfig.ContentUrl : "default"

    $httpMethod = $global:tsRestApiConfig.Method.$Method.HttpMethod
    $uri = "$($global:tsRestApiConfig.Method.$Method.Uri())/content"
    $revision = $global:tsRestApiConfig.Method.$Method.Revision

    for ($i = 0; $i -lt $Params.Count; $i++) {
        $uri = $uri -replace "<$($i)>",$Params[$i]
        $revision = $revision -replace "<$($i)>",$Params[$i]
    }
    
    $headers = $global:tsRestApiConfig.$($global:TsRestApiConfig.Method.$Method.EndpointVersioningType).Headers | Copy-Object
    $headers."Content-Type" = $headers."Content-Type".Replace("<ResourceString>",$global:tsRestApiConfig.Method.$Method.ResourceString)

    $tempOutFileDirectory = "$($global:Location.Root)\Data\$($global:tsRestApiConfig.Platform.Instance)\.export\$contentUrl\.temp"
    if (!(Test-Path $tempOutFileDirectory -PathType Container)) { New-Item -ItemType Directory -Path $tempOutFileDirectory | Out-Null }
    $tempOutFile = "$tempOutFileDirectory\$($InputObject.id)"
    Remove-Item -Path $tempOutFile -Force -ErrorAction SilentlyContinue

    try {
        $response = Invoke-RestMethod -Uri $uri -Method $httpMethod -Headers $headers -TimeoutSec $TimeoutSec -SkipCertificateCheck -SkipHttpErrorCheck -OutFile $tempOutFile -ResponseHeadersVariable responseHeaders
        $responseError = $null
        if ($global:tsRestApiConfig.Method.$Method.EndpointVersioningType -Eq "RestApiVersioning") {
            if ($response.$responseRoot.error) { return @{ error = $response.$responseRoot.error } }
        }
        else {
            if ($response.httpErrorCode) {
                return @{ error = [ordered]@{ code = $response.httpErrorCode; detail = $response.message } }
            }
        }
    }
    catch {
        return @{ error = $_.Exception.Message }
    }

    if ([string]::IsNullOrEmpty($responseHeaders."Content-Disposition")) {
        return @{ error = [ordered]@{ code = 404; summary = "Not Found"; detail = "$((Get-Culture).TextInfo.ToTitleCase($objectType)) download failed" }  }
    }      

    $projectPathDecoded = [System.Web.HttpUtility]::UrlDecode($projectPath)
    $contentDisposition = $responseHeaders."Content-Disposition".Split("; ")
    $contentDispositionFileName = $contentDisposition[1].Split("=")[1].Replace("`"","")
    $outFileNameLeafBase = [System.Web.HttpUtility]::UrlDecode($(Split-Path $contentDispositionFileName -LeafBase))
    $outFileExtension = [System.Web.HttpUtility]::UrlDecode($(Split-Path $contentDispositionFileName -Extension))
    $outFileName = $outFileNameLeafBase + ($revision ? ".rev$revision" : $null) + $outFileExtension
    $outFileDirectory = "$($global:Location.Root)\Data\$($global:tsRestApiConfig.Platform.Instance)\.export\$contentUrl\$projectPathDecoded$($revision ? "\$contentDispositionFileName.revisions" : $null)"
    $outFileDirectory = $outFileDirectory -replace "[<>|]", "-"
    if ($InputObject.location.type -eq "PersonalSpace") {
        $outFileDirectory += "Personal Space\$($InputObject.owner.name)\"
    }
    if (!(Test-Path -Path $outFileDirectory -PathType Container)) { New-Item -ItemType Directory -Path $outFileDirectory | Out-Null }
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
            [Parameter(Mandatory=$false)][switch]$ShowProgress = $global:ProgressPreference -eq "Continue"
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

            Set-CursorInvisible

            $message =  "<Uploading $Type `'$fileName`' <.>58> PENDING$($emptyString.PadLeft(9," "))"
            Write-Host+ -Iff $ShowProgress -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

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
                        $errorMessage += $responseError.summary
                    }
                    else {
                        $errorMessage += $responseError
                    }

                    $message = "$($emptyString.PadLeft(16,"`b"))FAILURE$($emptyString.PadLeft(16-$bytesUploaded.Length," "))"
                    Write-Host+ -Iff $ShowProgress -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor Red
                    Set-CursorVisible

                    $fileStream.Close()

                    throw $errorMessage
                    
                }

                $message = "$($emptyString.PadLeft(16,"`b"))$bytesReadTotalString","/","$fileSizeString$($emptyString.PadLeft(16-($bytesReadTotalString.Length + 1 + $fileSizeString.Length)," "))"
                Write-Host+ -Iff $ShowProgress -NoTrace -NoNewLine -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen,DarkGray,DarkGray

                $chunkCount++

            }

            $message = "$($emptyString.PadLeft(16,"`b"))$bytesReadTotalString","/","$fileSizeString$($emptyString.PadLeft(16-($bytesReadTotalString.Length + 1 + $fileSizeString.Length)," "))"
            Write-Host+ -Iff $ShowProgress -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen,DarkGray,DarkGreen

            Set-CursorVisible

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
                    $errorMessage = $responseError.summary
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

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false,ParameterSetName="ById")]
        [Parameter(Mandatory=$false,ParameterSetName="ByName")]
        [Parameter(Mandatory=$false,ParameterSetName="ByContentUrl")]
        [Parameter(Mandatory=$false,ParameterSetName="ByOwnerId")]
        [Alias("Sites","Projects","Groups","Users","Workbooks","Views","Datasources","Flows","Metrics","Collections","VirtualConnections","Favorites")]
        [object]
        $InputObject,

        [Parameter(Mandatory=$true,ParameterSetName="ById")]
        [Parameter(Mandatory=$true,ParameterSetName="ByName")]
        [Parameter(Mandatory=$true,ParameterSetName="ByContentUrl")]
        [Parameter(Mandatory=$false,ParameterSetName="ByOwnerId")]
        [ValidateSet("Site","Project","Group","User","Workbook","View","Datasource","Flow","Metric","Collection","VirtualConnection","Favorite")]
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

    if ($global:tsRestApiConfig.Platform.Id -eq "TableauCloud") { return Get-TSSite }

    return Get-TSObjects -Method GetSites | ConvertTo-PSCustomObject

}

function global:Get-TSSite {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method GetSite | ConvertTo-PSCustomObject

}

function global:Get-TSCurrentSite {

    [CmdletBinding()]
    param()

    return (Get-TSCurrentSession).site | ConvertTo-PSCustomObject

}

function global:Find-TSSite {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Sites,
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$ContentUrl,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )
    if ([string]::IsNullOrEmpty($Id) -and [string]::IsNullOrEmpty($Name) -and [string]::IsNullOrEmpty($ContentUrl)) {
        Write-Host+ "ERROR: The search parameters `$Id, `$Name and `$ContentUrl are null." -ForegroundColor Red
        return
    }
    if (!$Sites) { $Sites = Get-TSSites }
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
        [Parameter(Mandatory=$false)][object]$Users,
        [Parameter(Mandatory=$false)][switch]$ShowProgress = $global:ProgressPreference -eq "Continue"
    )

    $function = $PSCmdlet.MyInvocation.MyCommand.Name
    $callStack = Get-PSCallStack
    $caller = $callStack[1].Command -eq "<ScriptBlock>" ? "You" : "'$($callStack[1].Command)'"

    $recommendation = "[PERFORMANCE] $caller should use the '`$<lookupObject>' parameter to pass the <lookupObject> object<singularOrPlural> to '$function'."

    $lookupObjects = @()
    if (!$Users) { 
        $lookupObjects += "Users"
        $Users = Get-TSUsers
    }

    if ($lookupObjects) {
        $message = $recommendation -replace "<lookupObject>", ($lookupObjects -join ", ")
        $message = $message -replace "<singularOrPlural>", ($lookupObjects.Count -eq 1 ? $null : "s")
        Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGray
        Start-Sleep -Seconds 5
        Write-Host+ -ReverseLineFeed 2 -EraseLineToCursor
    }

    $site = Get-TSSite

    Set-CursorInvisible
    $usersPlus = @()
    $userIndex = 0
    $userCount = $Users.Count
    $Users | Foreach-Object {
        $userIndex++
        Write-Host+ -Iff $ShowProgress -NoTrace -NoTimeStamp -ReverseLineFeed 1 -EraseLine "[$userIndex/$userCount] $($_.Name)" -ForegroundColor DarkGray
        $usersPlus += Get-TSUser+ -Id $_.Id -Site $site
    }

    return $usersPlus
    
}

function global:Get-TSUser+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][object]$Site = (Get-TSSite)
    )

    $user = Get-TSUser -Id $Id
    $groups = Get-TSUserMembership -User $user
    $user | Add-Member -NotePropertyName membership -NotePropertyValue $groups
    $user | Add-Member -NotePropertyName site -NotePropertyValue $site

    return $user
    
}

function global:Get-TSUsers {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method GetUsers | ConvertTo-PSCustomObject

}

function global:Get-TSUser {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false,Position=0)][string]$Id = ((Get-TSCurrentUser).id)
    )

    return Get-TSObjects -Method GetUser -Params @($Id) | ConvertTo-PSCustomObject
}

function global:Get-TSCurrentUser {

    [CmdletBinding()]
    param()

    return (Get-TSCurrentSession).user

}

function global:Find-TSUser {

    [CmdletBinding()]
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

    return Get-TSObjects -Method GetUserMembership -Params @($User.Id) | ConvertTo-PSCustomObject

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
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][switch]$ShowProgress = $global:ProgressPreference -eq "Continue"
    )

    $groupIndex = 0
    $groupCount = $Groups.Count
    foreach ($group in $Groups) {
        $groupIndex++
        Write-Host+ -Iff $ShowProgress -NoTrace -NoTimeStamp -ReverseLineFeed 1 -EraseLine "[$groupIndex/$groupCount] $($group.Name)" -ForegroundColor DarkGray
        $users = Get-TSGroupMembership -Group $group
        $group | Add-Member -NotePropertyName membership -NotePropertyValue $users
    }

    $site = Get-TSCurrentSite
    $Groups | Add-Member -NotePropertyName site -NotePropertyValue $site

    return $Groups

}

function global:Get-TSGroups {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method GetGroups | ConvertTo-PSCustomObject
}

function global:Find-TSGroup {

    [CmdletBinding()]
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

function global:New-TSGroup {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Site,
        [Parameter(Mandatory=$false)][string]$Name
    )

    # $response is a group object or an error object
    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "AddGroupToSite" -Params @($Name)
    if ($responseError) {
        return
    }
    else {
        $tsGroup = $response # $response is a group object
        Write-Log -Action "AddGroupToSite" -Target "$($Site.contentUrl)\$($tsGroup.name)" -Message "$($tsGroup.name)" -Status "Success" -Force 
    }

    # $response is a group object, an update object or an error object
    return $response

}

function global:Get-TSGroupMembership {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Group
    )

    return Get-TSObjects -Method GetGroupMembership -Params @($Group.Id) | ConvertTo-PSCustomObject

}

function global:Add-TSUserToGroup {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Group,
        [Parameter(Mandatory=$true)][object]$User
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
        [Parameter(Mandatory=$true)][object]$User
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
        [Parameter(Mandatory=$false)][object]$Users,
        [Parameter(Mandatory=$false)][object]$Groups,
        [Parameter(Mandatory=$false)][object]$Projects,
        [Parameter(Mandatory=$false)][string]$Filter,
        [Parameter(Mandatory=$false)][switch]$ShowProgress = $global:ProgressPreference -eq "Continue"
    )

    $function = $PSCmdlet.MyInvocation.MyCommand.Name
    $callStack = Get-PSCallStack
    $caller = $callStack[1].Command -eq "<ScriptBlock>" ? "You" : "'$($callStack[1].Command)'"

    $recommendation = "[PERFORMANCE] $caller should use the '`$<lookupObject>' parameter to pass the <lookupObject> object<singularOrPlural> to '$function'."

    $lookupObjects = @()
    if (!$Users) { 
        $lookupObjects += "Users"
        $Users = Get-TSUsers
    }
    if (!$Groups) {
        $lookupObjects += "Groups"
        $Groups = Get-TSGroups
    }
    if (!$Projects) {
        $lookupObjects += "Projects"
        $Projects = Get-TSProjects -Filter $Filter
    }

    if ($lookupObjects) {
        $message = $recommendation -replace "<lookupObject>", ($lookupObjects -join ", ")
        $message = $message -replace "<singularOrPlural>", ($lookupObjects.Count -eq 1 ? $null : "s")
        Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGray
        Start-Sleep -Seconds 5
        Write-Host+ -ReverseLineFeed 2 -EraseLineToCursor
    }

    Set-CursorInvisible
    $projects = @()
    $projectIndex = 0
    $_projects = Get-TSProjects -Filter $Filter 
    $projectCount = $_projects.Count
    $_projects | Foreach-Object {
        $projectIndex++
        Write-Host+ -Iff $ShowProgress -NoTrace -NoTimeStamp -ReverseLineFeed 1 -EraseLine "[$projectIndex/$projectCount] $($_.Name)" -ForegroundColor DarkGray
        $projects += Get-TSProject+ -Id $_.id -Users $Users -Groups $Groups -Projects $_projects -Filter $Filter
    }
    Set-CursorVisible

    return $projects
}

function global:Get-TSProject+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$false)][object]$Users,
        [Parameter(Mandatory=$false)][object]$Groups,
        [Parameter(Mandatory=$false)][object]$Projects,
        [Parameter(Mandatory=$false)][string]$Filter
    )

    $function = $PSCmdlet.MyInvocation.MyCommand.Name
    $callStack = Get-PSCallStack
    $caller = $callStack[1].Command -eq "<ScriptBlock>" ? "You" : "'$($callStack[1].Command)'"

    $recommendation = "[PERFORMANCE] $caller should use the '`$<lookupObject>' parameter to pass the <lookupObject> object<singularOrPlural> to '$function'."

    $lookupObjects = @()
    if (!$Users) { 
        $lookupObjects += "Users"
        $Users = Get-TSUsers
    }
    if (!$Groups) {
        $lookupObjects += "Groups"
        $Groups = Get-TSGroups
    }
    if (!$Projects) {
        $lookupObjects += "Projects"
        $Projects = Get-TSProjects -Filter $Filter
    }

    if ($lookupObjects) {
        $message = $recommendation -replace "<lookupObject>", ($lookupObjects -join ", ")
        $message = $message -replace "<singularOrPlural>", ($lookupObjects.Count -eq 1 ? $null : "s")
        Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGray
        Start-Sleep -Seconds 5
        Write-Host+ -ReverseLineFeed 2 -EraseLineToCursor
    }

    $project = $projects | Where-Object {$_.id -eq $Id}
    if (!$project.Permissions) {
        $projectPermissions = Get-TSProjectPermissions+ -Users $Users -Groups $Groups -Projects $project
        $project | Add-Member -NotePropertyName permissions -NotePropertyValue $projectPermissions
    }

    return $project
}

function global:Get-TSProjects {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Filter
    )

    return Get-TSObjects -Method GetProjects -Filter $Filter | ConvertTo-PSCustomObject

}

function global:Find-TSProject {
    
    [CmdletBinding()]
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
    return Find-TSObject -Type "Project" -Projects $Projects @params | ConvertTo-PSCustomObject

}

function global:Get-TSProjectPermissions+ {

    param(
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+),
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups+),
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers+)
    )

    $projectPermissions = @()
    foreach ($project in $projects) {

        $permissions = Get-TSProjectPermissions -Project $project
        foreach ($permission in $permissions) {
            foreach ($granteeCapability in $permission.GranteeCapabilities) {
                if ($granteeCapability.user) {
                    $granteeCapabilityUser = Find-TSUser -Users $users -Id $granteeCapability.user.id
                    foreach ($member in $granteeCapabilityUser | Get-Member -MemberType Property) {
                        $granteeCapability.user | Add-Member -NotePropertyName $member.Name -NotePropertyValue $granteeCapabilityUser.($member.Name) -ErrorAction SilentlyContinue
                    }
                }
                elseif ($granteeCapability.group) {
                    $granteeCapabilityGroup = Find-TSGroup -Groups $Groups -Id $granteeCapability.group.id
                    foreach ($member in $granteeCapabilityGroup | Get-Member -MemberType Property) {
                        $granteeCapability.group | Add-Member -NotePropertyName $member.Name -NotePropertyValue $granteeCapabilityGroup.($member.Name) -ErrorAction SilentlyContinue
                    }
                }
            }
        }

        $defaultPermissions = Get-TSProjectDefaultPermissions+ -Project $project -Groups $Groups -Users $Users
        $permissions | Add-Member -NotePropertyName defaultPermissions -NotePropertyValue $defaultPermissions
        
        $projectPermissions += $permissions

    }

    return $projectPermissions

}

function global:Get-TSProjectPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Projects
    )

    $projectPermissions = @()
    foreach ($project in $Projects) {
        $projectPermissions += Get-TSObjects -Method GetProjectPermissions -Params @($Project.Id,$Type) | ConvertTo-PSCustomObject
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
    }
    
    return $response,$responseError
}

function global:Get-TSProjectDefaultPermissions+ {

    param(
        [Parameter(Mandatory=$false)]
        [object]$Projects = (Get-TSProjects+),
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("workbooks","datasources","dataroles","lenses","flows","metrics","databases")]
        [string[]]$Type = @("workbooks","datasources","dataroles","lenses","flows","metrics","databases"),
        
        [Parameter(Mandatory=$false)]
        [object]$Groups = (Get-TSGroups),
        
        [Parameter(Mandatory=$false)]
        [object]$Users = (Get-TSUsers)
    )

    $projectDefaultPermissions = @()
    foreach ($project in $Projects) {
        $permissions = Get-TSProjectDefaultPermissions -Projects $project -Type $Type
        foreach ($permission in $permissions) {
            foreach ($granteeCapability in $permission.GranteeCapabilities) {
                if ($granteeCapability.user) {
                    $granteeCapabilityUser = Find-TSUser -Users $users -Id $granteeCapability.user.id
                    foreach ($member in $granteeCapabilityUser | Get-Member -MemberType Property) {
                        $granteeCapability.user | Add-Member -NotePropertyName $member.Name -NotePropertyValue $granteeCapabilityUser.($member.Name) -ErrorAction SilentlyContinue
                    }
                }
                elseif ($granteeCapability.group) {
                    $granteeCapabilityGroup = Find-TSGroup -Groups $groups -Id $granteeCapability.group.id
                    foreach ($member in $granteeCapabilityGroup | Get-Member -MemberType Property) {
                        $granteeCapability.group | Add-Member -NotePropertyName $member.Name -NotePropertyValue $granteeCapabilityGroup.($member.Name) -ErrorAction SilentlyContinue
                    }
                }
            }
            $projectDefaultPermissions += $permissions
        }
    }

    return $projectDefaultPermissions
}

function global:Get-TSProjectDefaultPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Projects,
        [Parameter(Mandatory=$true)][ValidateSet("workbooks","datasources","dataroles","lenses","flows","metrics","databases")][string[]]$Type
    )

    $projectDefaultPermissions = @()
    foreach ($project in $Projects) {
        $_projectDefaultPermissions = @{}
        foreach ($_type in $Type) {
            $_projectDefaultPermissionsByType = Get-TSObjects -Method GetProjectDefaultPermissions -Params @($project.Id,$_type) | ConvertTo-PSCustomObject
            $_projectDefaultPermissions += @{ $($_type -replace ($_type -eq "lenses" ? "es$" : "s$"),"") = $_projectDefaultPermissionsByType }
        }
        $projectDefaultPermissions += $_projectDefaultPermissions | ConvertTo-PSCustomObject
    }
    
    return $projectDefaultPermissions
}

function global:Add-TSProjectDefaultPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Project,
        [Parameter(Mandatory=$true)][ValidateSet("workbooks","datasources","dataroles","lenses","flows","metrics","databases")][string]$Type, # "DataRoles"
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        [Parameter(Mandatory=$false)][string[]]$Capabilities 
    )

    switch ($Type) {
        "workbooks" { $Capabilities | Foreach-Object { if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.Workbook) { throw "$($_) is not a valid capability" } } }
        "datasources" { $Capabilities | Foreach-Object { if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.Datasource) { throw "$($_) is not a valid capability" } } }
        "dataroles" { $Capabilities | Foreach-Object { if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.DataRole) { throw "$($_) is not a valid capability" } } }
        "lenses" { $Capabilities | Foreach-Object { if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.Lens) { throw "$($_) is not a valid capability" } } }
        "flows" {$Capabilities | Foreach-Object { if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.Flow) { throw "$($_) is not a valid capability" } } }
        "metrics" { $Capabilities | Foreach-Object { if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.Metric) { throw "$($_) is not a valid capability" } } }
        "databases" { $Capabilities | Foreach-Object { if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.Database) { throw "$($_) is not a valid capability" } } }
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
    
    return $response,$responseError
}

function global:Remove-TSProjectDefaultPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Project,
        [Parameter(Mandatory=$true)][ValidateSet("workbooks","datasources","dataroles","lenses","flows","metrics","databases")][string]$Type,
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        [Parameter(Mandatory=$false)][string[]]$Capabilities 
    )

    switch ($Type) {
        "workbooks" { $Capabilities | Foreach-Object { if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.Workbook) { throw "$($_) is not a valid capability" } } }
        "datasources" { $Capabilities | Foreach-Object { if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.Datasource) { throw "$($_) is not a valid capability" } } }
        "dataroles" { $Capabilities | Foreach-Object { if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.DataRole) { throw "$($_) is not a valid capability" } } }
        "lenses" { $Capabilities | Foreach-Object { if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.Lens) { throw "$($_) is not a valid capability" } } }
        "flows" {$Capabilities | Foreach-Object { if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.Flow) { throw "$($_) is not a valid capability" } } }
        "metrics" { $Capabilities | Foreach-Object { if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.Metric) { throw "$($_) is not a valid capability" } } }
        "databases" { $Capabilities | Foreach-Object { if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.Database) { throw "$($_) is not a valid capability" } } }
    }
    
    if (!($Group -or $User) -or ($Group -and $User)) {
        throw "Must specify either Group or User"
    }

    $grantee = $Group ?? $User
    $granteeType = $Group ? "groups" : "users"

    foreach ($capability in $Capabilities) {
        $capabilityName,$capabilityMode = $capability.split(":")
        $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "RemoveProjectDefaultPermissions" -Params @($Project.id,$Type,$granteeType,$grantee.Id,$capabilityName,$capabilityMode)
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
        [Parameter(Mandatory=$false)][switch]$Download,
        [Parameter(Mandatory=$false)][switch]$ShowProgress = $global:ProgressPreference -eq "Continue"
    )

    Set-CursorInvisible
    $workbooks = @()
    $workbookIndex = 0
    $_workbooks = Get-TSworkbooks -Filter $Filter 
    $workbookCount = $_workbooks.Count
    $_workbooks | Foreach-Object {
        $workbookIndex++
        Write-Host+ -Iff $ShowProgress -NoTrace -NoTimeStamp -ReverseLineFeed 1 -EraseLine "[$workbookIndex/$workbookCount] $($_.Name)" -ForegroundColor DarkGray
        $workbooks += Get-TSWorkbook+ -Id $_.id -Users $Users -Groups $Groups -Projects $Projects -Filter $Filter -Download:$Download.IsPresent
    }
    Set-CursorVisible

    return $workbooks

}

function global:Get-TSWorkbook+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers),
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+),
        [Parameter(Mandatory=$false)][string]$Filter,
        [Parameter(Mandatory=$false)][switch]$Download
    )

    $workbook = Get-TSWorkbook -Id $Id -Download:$Download.IsPresent

    $workbookPermissions = Get-TSWorkbookPermissions+ -Users $Users -Groups $Groups -Workbooks $workbook
    $workbookRevisions = Get-TSWorkbookRevisions -Workbook $workbook
    $workbookConnections = Get-TSWorkbookConnections -Id $workbook.id

    $workbook | Add-Member -NotePropertyName permissions -NotePropertyValue $workbookPermissions
    $workbook | Add-Member -NotePropertyName revisions -NotePropertyValue $workbookRevisions
    $workbook | Add-Member -NotePropertyName connections -NotePropertyValue $workbookConnections

    return $workbook
}

function global:Get-TSWorkbooks {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Filter,
        [switch]$Download
    )

    return Get-TSObjects -Method GetWorkbooks -Filter $Filter -Download:$Download.IsPresent | ConvertTo-PSCustomObject

}

function global:Get-TSWorkbook {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [switch]$Download
    )

    return Get-TSObjects -Method GetWorkbook -Params @($Id) -Download:$Download.IsPresent | ConvertTo-PSCustomObject

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

function global:Find-TSWorkbook {

    [CmdletBinding()]
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
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups+),
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers+)
    )
    
    $workbookPermissions = @()
    foreach ($workbook in $workbooks) {
        $permissions = Get-TSWorkbookPermissions -Workbook $Workbook
        foreach ($permission in $permissions) {
            foreach ($granteeCapability in $permission.GranteeCapabilities) {
                if ($granteeCapability.user) {
                    $granteeCapabilityUser = Find-TSUser -Users $users -Id $granteeCapability.user.id
                    foreach ($member in $granteeCapabilityUser | Get-Member -MemberType Property) {
                        $granteeCapability.user | Add-Member -NotePropertyName $member.Name -NotePropertyValue $granteeCapabilityUser.($member.Name) -ErrorAction SilentlyContinue
                    }
                }
                elseif ($granteeCapability.group) {
                    $granteeCapabilityGroup = Find-TSGroup -Groups $groups -Id $granteeCapability.group.id
                    foreach ($member in $granteeCapabilityGroup | Get-Member -MemberType Property) {
                        $granteeCapability.group | Add-Member -NotePropertyName $member.Name -NotePropertyValue $granteeCapabilityGroup.($member.Name) -ErrorAction SilentlyContinue
                    }
                }
            }
            $workbookPermissions += $permissions
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
    
    return Get-TSObjects -Method "GetWorkbookPermissions" -Params @($Workbook.Id) | ConvertTo-PSCustomObject

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
        if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.Workbook) {
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

    return $response,$responseError
}

function global:Get-TSWorkbookConnections {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id
    )

    return Get-TSObjects -Method GetWorkbookConnections -Params @($Id)  | ConvertTo-PSCustomObject
    
}

function global:Get-TSWorkbookRevisions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Workbook,
        [Parameter(Mandatory=$false)][string]$Revision,
        [switch]$Download
    )

    $workbookRevisions = Get-TSObjects -Method GetWorkbookRevisions -Params @($Workbook.Id) | ConvertTo-PSCustomObject
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
        [Parameter(Mandatory=$false)][object]$Workbooks,
        [Parameter(Mandatory=$false)][string]$Filter,
        [Parameter(Mandatory=$false)][switch]$ShowProgress = $global:ProgressPreference -eq "Continue"
    )

    Set-CursorInvisible
    $views = @()
    $viewIndex = 0
    $_views = Get-TSviews -Filter $Filter 
    $viewCount = $_views.Count
    $_views | Foreach-Object {
        $viewIndex++
        Write-Host+ -Iff $ShowProgress -NoTrace -NoTimeStamp -ReverseLineFeed 1 -EraseLine "[$viewIndex/$viewCount] $($_.Name)" -ForegroundColor DarkGray
        $views += Get-TSView+ -Id $_.id -Users $Users -Groups $Groups -Projects $Projects -Filter $Filter
    }
    Set-CursorVisible

    return $views
}

function global:Get-TSView+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers),
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+),
        [Parameter(Mandatory=$false)][string]$Filter
    )

    $view = Get-TSView -Id $Id

    $viewPermissions = Get-TSViewPermissions+ -Users $Users -Groups $Groups -Views $view
    $view | Add-Member -NotePropertyName permissions -NotePropertyValue $viewPermissions

    return $view
}

function global:Get-TSView {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Id
    )

    return Get-TSObjects -Method "GetView" -Params @($Id) | ConvertTo-PSCustomObject

}

function global:Get-TSViews {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Filter
    )

    return Get-TSObjects -Method "GetViewsForSite" -Filter $Filter | ConvertTo-PSCustomObject

}

function global:Get-TSViewsForWorkbook {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Workbook,
        [Parameter(Mandatory=$false)][string]$Filter
    )

    return Get-TSObjects -Method "GetViewsForWorkbook" -Params @($Workbook.id) | ConvertTo-PSCustomObject

}

function global:Find-TSView {

    [CmdletBinding()]
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

    $viewPermissions = @()
    foreach ($view in $views) {
        $permissions = Get-TSViewPermissions -View $View
        foreach ($permission in $permissions) {
            foreach ($granteeCapability in $permission.GranteeCapabilities) {
                if ($granteeCapability.user) {
                    $granteeCapabilityUser = Find-TSUser -Users $users -Id $granteeCapability.user.id
                    foreach ($member in $granteeCapabilityUser | Get-Member -MemberType Property) {
                        $granteeCapability.user | Add-Member -NotePropertyName $member.Name -NotePropertyValue $granteeCapabilityUser.($member.Name) -ErrorAction SilentlyContinue
                    }
                }
                elseif ($granteeCapability.group) {
                    $granteeCapabilityGroup = Find-TSGroup -Groups $groups -Id $granteeCapability.group.id
                    foreach ($member in $granteeCapabilityGroup | Get-Member -MemberType Property) {
                        $granteeCapability.group | Add-Member -NotePropertyName $member.Name -NotePropertyValue $granteeCapabilityGroup.($member.Name) -ErrorAction SilentlyContinue
                    }
                }
            }
            $viewPermissions += $permissions
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

    return Get-TSObjects -Method "GetViewPermissions" -Params @($View.Id) | ConvertTo-PSCustomObject
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
        if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.View) {
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
        [Parameter(Mandatory=$false)][switch]$Download,
        [Parameter(Mandatory=$false)][switch]$ShowProgress = $global:ProgressPreference -eq "Continue"
    )

    Set-CursorInvisible
    $datasources = @()
    $datasourceIndex = 0
    $_datasources = Get-TSdatasources -Filter $Filter 
    $datasourceCount = $_datasources.Count
    $_datasources | Foreach-Object {
        $datasourceIndex++
        Write-Host+ -Iff $ShowProgress -NoTrace -NoTimeStamp -ReverseLineFeed 1 -EraseLine "[$datasourceIndex/$datasourceCount] $($_.Name)" -ForegroundColor DarkGray
        $datasources += Get-TSDatasource+ -Id $_.id -Users $Users -Groups $Groups -Projects $Projects -Filter $Filter -Download:$Download.IsPresent
    }
    Set-CursorVisible

    return $datasources

}

function global:Get-TSDatasource+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers),
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+),
        [Parameter(Mandatory=$false)][string]$Filter,
        [Parameter(Mandatory=$false)][switch]$Download
    )

    $datasource = Get-TSDatasource -Id $Id -Download:$Download.IsPresent

    $datasourcePermissions = Get-TSDatasourcePermissions+ -Users $Users -Groups $Groups -Datasource $datasource
    $datasourceRevisions = Get-TSDatasourceRevisions -Datasource $datasource
    $datasourceConnections = Get-TSDatasourceConnections -Id $datasource.id

    $datasource | Add-Member -NotePropertyName permissions -NotePropertyValue $datasourcePermissions
    $datasource | Add-Member -NotePropertyName revisions -NotePropertyValue $datasourceRevisions
    $datasource | Add-Member -NotePropertyName connections -NotePropertyValue $datasourceConnections

    return $datasource

}

function global:Get-TSDatasources {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Filter,
        [switch]$Download
    )

    return Get-TSObjects -Method GetDatasources -Filter $Filter -Download:$Download.IsPresent | ConvertTo-PSCustomObject

}

function global:Get-TSDatasource {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [switch]$Download
    )

    return Get-TSObjects -Method GetDatasource -Params @($Id) -Download:$Download.IsPresent | ConvertTo-PSCustomObject
}

function global:Update-TSDatasource {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Datasource,
        [Parameter(Mandatory=$false)][object]$Project = $Datasource.Project,
        [Parameter(Mandatory=$false)][object]$Owner = $Datasource.Owner
    )

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method UpdateDatasource -Params @($Datasource.Id, $Datasource.Name, $Project.Id, $Owner.Id) 

    return $response, $responseError

}

function global:Get-TSDatasourceRevisions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Datasource,
        [Parameter(Mandatory=$false)][string]$Revision,
        [switch]$Download
    )

    $datasourceRevisions = Get-TSObjects -Method GetDatasourceRevisions -Params @($Datasource.Id) | ConvertTo-PSCustomObject
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

function global:Get-TSDatasourceConnections {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id
    )

    return Get-TSObjects -Method GetDatasourceConnections -Params @($Id) | ConvertTo-PSCustomObject
}

function global:Find-TSDatasource {

    [CmdletBinding()]
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
    
    $datasourcePermissions = @()
    foreach ($datasource in $datasources) {
        $permissions = Get-TSDatasourcePermissions -Datasource $Datasource
        foreach ($permission in $permissions) {
            foreach ($granteeCapability in $permission.GranteeCapabilities) {
                if ($granteeCapability.user) {
                    $granteeCapabilityUser = Find-TSUser -Users $users -Id $granteeCapability.user.id
                    foreach ($member in $granteeCapabilityUser | Get-Member -MemberType Property) {
                        $granteeCapability.user | Add-Member -NotePropertyName $member.Name -NotePropertyValue $granteeCapabilityUser.($member.Name) -ErrorAction SilentlyContinue
                    }
                }
                elseif ($granteeCapability.group) {
                    $granteeCapabilityGroup = Find-TSGroup -Groups $groups -Id $granteeCapability.group.id
                    foreach ($member in $granteeCapabilityGroup | Get-Member -MemberType Property) {
                        $granteeCapability.group | Add-Member -NotePropertyName $member.Name -NotePropertyValue $granteeCapabilityGroup.($member.Name) -ErrorAction SilentlyContinue
                    }
                }
            }
            $datasourcePermissions += $permissions
        }
    }

    return $datasourcePermissions
}

function global:Get-TSDatasourcePermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Datasource
    )

    if ($Datasource.location.type -eq "PersonalSpace") {
        $responseError = "Method 'GetDatasourcePermissions' is not authorized for datasources in a personal space."
        Write-Log -EntryType "Error" -Action "GetDatasourcePermissions" -Target "datasources\$($Datasource.id)" -Status "Forbidden" -Message $responseError 
        return
    }

    return Get-TSObjects -Method GetDatasourcePermissions -Params @($Datasource.Id) | ConvertTo-PSCustomObject
}

function global:Add-TSDatasourcePermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Datasource,
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        [Parameter(Mandatory=$false)][string[]]$Capabilities 
    )

    if (!($Group -or $User) -or ($Group -and $User)) {
        throw "Must specify either Group or User"
    }

    
    $Capabilities | Foreach-Object {
        if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.Datasource) {
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

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "AddDatasourcePermissions" -Params @($Datasource.id,$capabilityXML)
    
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
        [Parameter(Mandatory=$false)][switch]$Download,
        [Parameter(Mandatory=$false)][switch]$ShowProgress = $global:ProgressPreference -eq "Continue"
    )

    Set-CursorInvisible
    $flows = @()
    $flowIndex = 0
    $_flows = Get-TSflows -Filter $Filter 
    $flowCount = $_flows.Count
    $_flows | Foreach-Object {
        $flowIndex++
        Write-Host+ -Iff $ShowProgress -NoTrace -NoTimeStamp -ReverseLineFeed 1 -EraseLine "[$flowIndex/$flowCount] $($_.Name)" -ForegroundColor DarkGray
        $flows += Get-TSFlow+ -Id $_.id -Users $Users -Groups $Groups -Projects $Projects -Filter $Filter -Download:$Download.IsPresent
    }
    Set-CursorVisible

    return $flows

}

function global:Get-TSFlow+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers),
        [Parameter(Mandatory=$false)][object]$Groups = (Get-TSGroups),
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+),
        [Parameter(Mandatory=$false)][string]$Filter,
        [Parameter(Mandatory=$false)][switch]$Download
    )

    $flow = Get-TSFlow -Id $Id -Download:$Download.IsPresent

    $flowPermissions = Get-TSFlowPermissions+ -Users $Users -Groups $Groups -Flows $flow
    $flowRevisions = Get-TSFlowRevisions -Flow $flow
    $flowConnections = Get-TSFlowConnections -Id $flow.id

    $flow | Add-Member -NotePropertyName permissions -NotePropertyValue $flowPermissions
    $flow | Add-Member -NotePropertyName revisions -NotePropertyValue $flowRevisions
    $flow | Add-Member -NotePropertyName connections -NotePropertyValue $flowConnections

    return $flow
}

function global:Get-TSFlows {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Filter,
        [switch]$Download
    )

    return Get-TSObjects -Method GetFlows -Filter $Filter -Download:$Download.IsPresent | ConvertTo-PSCustomObject

}

function global:Get-TSFlowsForUser {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Filter,
        [switch]$Download
    )

    return Get-TSObjects -Method GetFlowsForUser -Filter $Filter -Download:$Download.IsPresent | ConvertTo-PSCustomObject

}

function global:Get-TSFlow {

    [CmdletBinding()]
    param(        
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [switch]$Download
    )

    $flow = Get-TSObjects -Method GetFlow -Params @($Id) | ConvertTo-PSCustomObject
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

    [CmdletBinding()]
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

    $flowPermissions = @()
    foreach ($flow in $flows) {
        $permissions = Get-TSFlowPermissions -Flow $Flow
        foreach ($permission in $permissions) {
            foreach ($granteeCapability in $permission.GranteeCapabilities) {
                if ($granteeCapability.user) {
                    $granteeCapabilityUser = Find-TSUser -Users $users -Id $granteeCapability.user.id
                    foreach ($member in $granteeCapabilityUser | Get-Member -MemberType Property) {
                        $granteeCapability.user | Add-Member -NotePropertyName $member.Name -NotePropertyValue $granteeCapabilityUser.($member.Name) -ErrorAction SilentlyContinue
                    }
                }
                elseif ($granteeCapability.group) {
                    $granteeCapabilityGroup = Find-TSGroup -Groups $groups -Id $granteeCapability.group.id
                    foreach ($member in $granteeCapabilityGroup | Get-Member -MemberType Property) {
                        $granteeCapability.group | Add-Member -NotePropertyName $member.Name -NotePropertyValue $granteeCapabilityGroup.($member.Name) -ErrorAction SilentlyContinue
                    }
                }
            }
            $flowPermissions += $permissions
        }
    }

    return $flowPermissions
}

function global:Get-TSFlowPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Flow
    )

    if ($Flow.location.type -eq "PersonalSpace") {
        $responseError = "Method 'GetFlowPermissions' is not authorized for flows in a personal space."
        Write-Log -EntryType "Error" -Action "GetFlowPermissions" -Target "flows\$($Flow.id)" -Status "Forbidden" -Message $responseError 
        return
    }

    return Get-TSObjects -Method GetFlowPermissions -Params @($Flow.Id) | ConvertTo-PSCustomObject

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
        if ($_ -notin $global:tsRestApiConfig.Defaults.Permissions.Flow) {
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

function global:Get-TSFlowConnections {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id
    )

    return Get-TSObjects -Method GetFlowConnections -Params @($Id)  | ConvertTo-PSCustomObject
    
}

function global:Get-TSFlowRevisions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Flow,
        [Parameter(Mandatory=$false)][string]$Revision,
        [switch]$Download
    )

    $flowRevisions = Get-TSObjects -Method GetFlowRevisions -Params @($Flow.Id) | ConvertTo-PSCustomObject
    if ($Revision) { $flowRevisions = $flowRevisions | Where-Object {$_.revisionNumber -eq $Revision} }
    
    if ($flowRevisions -and $Download) {
        foreach ($flowRevision in $flowRevisions) {
            $response = Download-TSObject -Method GetFlowRevision -InputObject $Flow -Params @($Flow.Id, $flowRevision.revisionNumber)
            if ($response.error) {
                $errorMessage = "Error $($response.error.code) ($($response.error.summary)): $($response.error.detail)"
                Write-Log -Message $errorMessage -EntryType "Error" -Action $Method -Status "Error"
                $flowRevision.SetAttribute("error", ($response | ConvertTo-Json -Compress))
            }
            else {
                $flowRevision.SetAttribute("outFile", $response.outFile)
            }
        }
    }

    return $flowRevisions

}

function global:Get-TSFlowRevision {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Flow,
        [Parameter(Mandatory=$true)][string]$Revision,
        [switch]$Download
    )

    return Get-TSFlowRevisions -Flow $Flow -Revision $Revision -Download:$Download.IsPresent

}
#endregion FLOWS
#region METRICS

    function global:Get-TSMetrics {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false)][string]$Filter
        )

        return Get-TSObjects -Method GetMetrics -Filter $Filter | ConvertTo-PSCustomObject
    }

    function global:Get-TSMetric {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)][string]$MetricLuid
        )

        return Get-TSObjects -Method GetMetric -Params @($MetricLuid) | ConvertTo-PSCustomObject
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

    function global:Find-TSMetric {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false)][object]$Metrics,
            [Parameter(Mandatory=$false)][string]$Id,
            [Parameter(Mandatory=$false)][string]$Name,
            [Parameter(Mandatory=$false)][object]$Owner,
            [Parameter(Mandatory=$false)][string]$Operator="eq"
        )
        
        if ([string]::IsNullOrEmpty($Id) -and [string]::IsNullOrEmpty($Name) -and [string]::IsNullOrEmpty($Owner)) {
            Write-Host+ "ERROR: The search parameters `$Id, `$Name and `$Owner are null." -ForegroundColor Red
            return
        }
        if (!$Metrics) { $Metrics = Get-TSMetrics }
        $params = @{Operator = $Operator}
        if ($Id) {$params += @{Id = $Id}}
        if ($Name) {$params += @{Name = $Name}}
        if ($Owner) {$params += @{OwnerId = $Owner.id}}
        return Find-TSObject -Type "Metric" -Metrics $Metrics @Params

    }

#endregion METRICS
#region COLLECTIONS

    function global:Get-TSCollections {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false)][object]$User=(Get-TSCurrentUser)
        )

        return Get-TSObjects -Method GetCollections | ConvertTo-PSCustomObject

    }


    function global:Find-TSCollection {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false)][object]$Collections,
            [Parameter(Mandatory=$false)][string]$Id,
            [Parameter(Mandatory=$false)][string]$Name,
            [Parameter(Mandatory=$false)][object]$Owner,
            [Parameter(Mandatory=$false)][string]$Operator="eq"
        )
        
        if ([string]::IsNullOrEmpty($Id) -and [string]::IsNullOrEmpty($Name) -and [string]::IsNullOrEmpty($Owner)) {
            Write-Host+ "ERROR: The search parameters `$Id, `$Name and `$Owner are null." -ForegroundColor Red
            return
        }
        if (!$Collections) { $Collections = Get-TSCollections }
        $params = @{Operator = $Operator}
        if ($Id) {$params += @{Id = $Id}}
        if ($Name) {$params += @{Name = $Name}}
        if ($Owner) {$params += @{OwnerId = $Owner.id}}
        return Find-TSObject -Type "Collection" -Collections $Collections @Params

    }

#endregion COLLECTIONS
#region VIRTUALCONNECTIONS

    function global:Get-TSVirtualConnections {

        [CmdletBinding()]
        param(  
            [Parameter(Mandatory=$false)][string]$Filter
        )

        return Get-TSObjects -Method GetVirtualConnections | ConvertTo-PSCustomObject
    }

    function global:Find-TSVirtualConnection {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false)][object]$VirtualConnections,
            [Parameter(Mandatory=$false)][string]$Id,
            [Parameter(Mandatory=$false)][string]$Name,
            [Parameter(Mandatory=$false)][object]$Owner,
            [Parameter(Mandatory=$false)][string]$Operator="eq"
        )

        if ([string]::IsNullOrEmpty($Id) -and [string]::IsNullOrEmpty($Name) -and [string]::IsNullOrEmpty($Owner)) {
            Write-Host+ "ERROR: The search parameters `$Id, `$Name and `$Owner are null." -ForegroundColor Red
            return
        }
        if (!$VirtualConnections) { $VirtualConnections = Get-TSVirtualConnections }
        $params = @{Operator = $Operator}
        if ($Id) {$params += @{Id = $Id}}
        if ($Name) {$params += @{Name = $Name}}
        if ($Owner) {$params += @{OwnerId = $Owner.id}}
        return Find-TSObject -Type "VirtualConnection" -VirtualConnections $VirtualConnections @Params

    }

#endregion VIRTUALCONNECTIONS
#region FAVORITES

function global:Get-TSFavorites+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Site = (Get-TSCurrentSite),
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSCurrentUser),
        [switch]$All
    )

    # $response = Get-TSObjects -Method GetFavorites -Params @($User.id)

    function New-FavoritePlus {

        param(
            [Parameter(Mandatory=$false)][object]$User,
            [Parameter(Mandatory=$true)][object]$Favorites
        )

        $originalSite = Get-TSCurrentSite
        $currentSite = Get-TSCurrentSite

        $favoritesPlus = @()
        foreach ($favorite in $Favorites) {

            $favoriteSite = Find-TSSite -Id $favorite.site_luid
            if ($currentSite.contentUrl -ne $favoriteSite.contentUrl) {
                Switch-TSSite -ContentUrl $favoriteSite.contentUrl
                $currentSite = $favoriteSite
            }

            $type = $favorite.type.ToLower()

            $favoritePlus = [PSCustomObject]@{
                label = $favorite.label
                position = $favorite.position
                addedAt = $favorite.addedAt
                type = $type
                $type = $null
                "$($type)Id" = $favorite.useable_luid
                deleted = $favorite.deleted
                owner = Get-TSUser -Id $favorite.user_luid
                site = $favoriteSite
            }

            if (!$favorite.deleted) {
                $favoritePlus.($type) = Invoke-Expression "Find-TS$($type) -Id $($favorite.useable_luid)"
            }

            $favoritesPlus += $favoritePlus

        }

        Switch-TSSite -ContentUrl $originalSite.contentUrl

        return $favoritesPlus

    }

    if ($All) {
        $favorites = Get-TSFavorites -All:$All.IsPresent
        $favoritesPlus = New-FavoritePlus -Favorites $favorites
    }
    else {
        foreach ($user in $Users) {
            $favorites = Get-TSFavorites -Site $Site -User $user
            $favoritesPlus = New-FavoritePlus -Favorites $favorites -User $user
        }
    }

    return $favoritesPlus

}

function global:Get-TSFavorites {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Site = (Get-TSCurrentSite),
        [Parameter(Mandatory=$false)][object]$User = (Get-TSCurrentUser),
        [switch]$All
    )

    # $response = Get-TSObjects -Method GetFavorites -Params @($User.id)

    $query = "select ali.id as id,s.luid as site_luid,u.luid as user_luid,ali.usedobj_name as label,ali.position,ali.added_timestamp as addedat,ali.useable_type as type,ali.useable_id,ali.useable_luid,ali.suspected_as_deleted as deleted from asset_lists al join asset_list_items ali on al.id = ali.asset_list_id join sites s on al.site_id = s.id join users u on al.owner_id = u.id join system_users su on u.system_user_id = su.id"
    $filter = $All ? "" : "s.name = '$($Site.name)' and su.name = '$($User.name)'"
    $response = read-postgresdata -database workgroup -query $query -filter $filter

    return $response

}

function global:Find-TSFavorite {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$User,
        [Parameter(Mandatory=$false)][object]$Favorites = (Get-TSFavorites -User $User),
        [Parameter(Mandatory=$true)][Alias("Label")][string]$Name,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )

    $params = @{Operator = $Operator}
    if ($Name) {$params += @{Name = $Name}}
    return Find-TSObject -Type "Favorite" -Favorites $Favorites @Params

}

function global:Add-TSFavorites {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Favorites
    )

    foreach ($favorite in $favorites) {
        $response = Add-TSFavorite -User $favorite.owner -Label $favorite.label -Type $favorite.type -InputObject $favorite.($favorite.type)
    }

    return $response

}

function global:Add-TSFavorite {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$User,
        [Parameter(Mandatory=$true)][string]$Label,
        [Parameter(Mandatory=$true)][ValidateSet("Project","Workbook","View","Datasource","Flow","Metric","Collection","VirtualConnection")][string]$Type,
        [Parameter(Mandatory=$true)][Alias("Project","Workbook","View","Datasource","Flow","Metric","Collection","VirtualConnection")][object]$InputObject,
        [switch]$ShowIsEmpty
    )

    $_attempt = 0; $_maxAttempts = 3;
    do {
        $_label = $Label.replace("&","&amp;") + $emptySTring.PadLeft($_attempt," ")
        $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "AddFavorite" -Params @($User.id,$_label,$Type,$InputObject.id) 
        $_attempt++          
    } while (
        $null -ne $responseError -and $responseError.StartsWith("Resource Conflict") -and $_attempt -le $_maxAttempts
    )
    if ($responseError) {
        throw $responseError
    }

    $favoritesPlus = @()
    foreach ($favorite in $response) {

        $favoritePlus = [PSCustomObject]@{
            label = $favorite.label
            position = [int]$favorite.position
            addedAt = [datetime]$favorite.addedAt
            isEmpty = $favorite.IsEmpty
        }

        $favoritePlusMembers = $favoritePlus | Get-Member -MemberType NoteProperty
        $favoriteMembers = $favorite | Get-Member -MemberType Property  | Where-Object {$_.name -notin $favoritePlusMembers.name}
        foreach ($member in $favoriteMembers) {
            $favoritePlus | Add-Member -NotePropertyName $member.Name -NotePropertyValue $favorite.($member.Name)
            $favoritePlus | Add-Member -NotePropertyName "type" -NotePropertyValue $member.Name
        }

        $favoritesPlus += $favoritePlus

    }

    return ($ShowIsEmpty ? $favoritesPlus : ($favoritesPlus | Where-Object {!$_.IsEmpty} | Select-Object -ExcludeProperty IsEmpty))

}

function global:Remove-TSFavorite {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$User,
        [Parameter(Mandatory=$true)][ValidateSet("Project","Workbook","View","Datasource","Flow","Metric","Collection","VirtualConnection")][string]$Type,
        [Parameter(Mandatory=$true)][Alias("Project","Workbook","View","Datasource","Flow","Metric","Collection","VirtualConnection")][object]$InputObject
    )

    $response, $pagination, $responseError = Invoke-TSRestApiMethod -Method "RemoveFavorite" -Params @($User.id,"$($Type)s",$InputObject.id)
    if ($responseError) {
        throw $responseError
    }

    return $response

}

    function global:Repair-TSFavorites {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false)][object]$Site = (Get-TSCurrentSite),
            [Parameter(Mandatory=$false)][object]$User = (Get-TSCurrentUser),
            [switch]$All,
            [switch]$Quiet
        )
    
        $favorites = $All ? (Get-TSFavorites -All) : (Get-TSFavorites -Site $Site -User $User)
        $orphanedFavorites = $favorites | Where-Object {$_.deleted}
        Write-Host+ -Iff $(!$Quiet.IsPresent) -NoTimestamp "Found $($orphanedFavorites.Count.ToString()) orphaned favorite$($orphanedFavorites.Count -ne 1 ? 's' : '')." -ForegroundColor DarkGray
        if (!$orphanedFavorites) { return }

        $table = "asset_list_items"
        $filter = $All ? "suspected_as_deleted" : "id in ($($orphanedFavorites.id -join ","))"
        $rowsAffected = Remove-PostgresData -Database workgroup -Table $table -Filter $filter
        Write-Host+ -Iff $(!$Quiet.IsPresent) -NoTimestamp "Removed $($rowsAffected.ToString()) orphaned favorite$($orphanedFavorites.Count -ne 1 ? 's' : '')." -ForegroundColor DarkGray
    
        return
    
    }

#endregion FAVORITES
#region SCHEDULES

function global:Get-TSSchedules {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method GetSchedules | ConvertTo-PSCustomObject

}

function global:Get-TSSchedule {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id
    )

    return Get-TSObjects -Method GetSchedule -Params @($Id) | ConvertTo-PSCustomObject

}

#endregion SCHEDULES    
#region SUBSCRIPTIONS

function global:Get-TSSubscriptions {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method GetSubscriptions | ConvertTo-PSCustomObject

}

function global:Get-TSSubscription {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id
    )

    return Get-TSObjects -Method GetSubscription -Params @($Id) | ConvertTo-PSCustomObject

}

#endregion SUBSCRIPTIONS 
#region NOTIFICATIONS

function global:Get-TSDataAlerts {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method GetDataAlerts | ConvertTo-PSCustomObject

}

function global:Get-TSDataAlert {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id
    )

    return Get-TSObjects -Method GetDataAlert -Params @($Id) | ConvertTo-PSCustomObject

}

function global:Get-TSUserNotificationPreferences {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method GetUserNotificationPreferences | ConvertTo-PSCustomObject

}

#endregion NOTIFICATIONS
#region WEBHOOKS

function global:Get-TSWebhooks {

    [CmdletBinding()]
    param()

    return Get-TSObjects -Method GetWebhooks | ConvertTo-PSCustomObject

}

function global:Get-TSWebhook {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id
    )

    return Get-TSObjects -Method GetWebhook -Params @($Id) | ConvertTo-PSCustomObject

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

    return @{ $key = $tsObject } | Add-TSAnalyticsExtensionsMeta -Target $Target | ConvertTo-PSCustomObject

}

function global:Get-TSAnalyticsExtensionsEnabledState {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false,Position=0)][ValidateSet("Site")][string]$Target = "Site"
    )

    $method = "GetAnalyticsExtensionsEnabledStateFor$Target"
    $key = ($global:tsRestApiConfig.Method.$method.Response.Keys).Split(".")[0]
    $tsObject = (Get-TSObjects -Method $method)

    return @{ $key = $tsObject } | Add-TSAnalyticsExtensionsMeta -Target $Target | ConvertTo-PSCustomObject

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

    return Get-TSObjects -Method "GetConnectedApplications" | ConvertTo-PSCustomObject

}

function global:Get-TSConnectedApplication {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ClientId
    )

    return Get-TSObjects -Method "GetConnectedApplications" -Params @($ClientId) | ConvertTo-PSCustomObject

}

#endregion CONNECTED APPLICATIONS