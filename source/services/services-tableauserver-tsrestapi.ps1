
#region CONFIG
function global:Initialize-TSRestApiConfiguration {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Server = "localhost",
        [Parameter(Mandatory=$false)][string]$Credentials = "localadmin-$($Platform.Instance)"
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $global:tsRestApiConfig = @{
        Server = $Server ? $Server : ($tsmApiConfig.Server ? $tsmApiConfig.Server : "localhost")
        ApiVersion = $global:Platform.Api.TsRestApiVersion ? $global:Platform.Api.TsRestApiVersion : "3.6"
        Credentials = $Credentials
        Token = $null
        SiteId = $null
        ContentUrl = ""
        ContentType = "application/xml;charset=utf-8"
        UserId = $null
        SpecialAccounts = @("guest","tableausvc","TabSrvAdmin","alteryxsvc")
        SpecialGroups = @("All Users")
        SpecialMethods = @("ServerInfo","Login")
    }

    $global:tsRestApiConfig.Headers = @{"Content-Type" = $global:tsRestApiConfig.ContentType}
    $global:tsRestApiConfig.ApiUri = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.ApiVersion)"
    
    $global:tsRestApiConfig.Method = @{
        Login = @{
            Path = "$($global:tsRestApiConfig.ApiUri)/auth/signin"
            HttpMethod = "POST"
            Body = "<tsRequest><credentials name='<0>' password='<1>'><site contentUrl='<2>'/></credentials></tsRequest>"
            Response = @{Keys = "credentials"}
        } 
        ServerInfo = @{
            Path = "$($global:tsRestApiConfig.ApiUri)/serverinfo"
            HttpMethod = "GET"
            Response = @{Keys = "serverinfo"}
        }
    }

    $serverInfo = Get-TsServerInfo -Update
    $serverInfo | Out-Null

    # $response = Invoke-TsLogin
    # $response | Out-Null

    $creds = Get-Credentials $global:tsRestApiConfig.Credentials

    $response,$pagination,$responseError = Invoke-TSRestApiMethod -Method Login -Params @($creds.UserName,$creds.GetNetworkCredential().Password,$ContentUrl)

    $global:tsRestApiConfig.Token = $response.token
    $global:tsRestApiConfig.SiteId = $response.site.id
    $global:tsRestApiConfig.ContentUrl = $response.site.contentUrl
    $global:tsRestApiConfig.UserId = $response.user.id 
    $global:tsRestApiConfig.Headers = @{"Content-Type" = "application/xml;charset=utf-8"; "X-Tableau-Auth" = $global:tsRestApiConfig.Token}

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
                Path = "$($global:tsRestApiConfig.ApiUri)/auth/signin"
                HttpMethod = "POST"
                Body = "<tsRequest><credentials name='<0>' password='<1>'><site contentUrl='<2>'/></credentials></tsRequest>"
                Response = @{Keys = "credentials"}
            } 
            GetCurrentSession = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sessions/current"
                HttpMethod = "GET"
                Response = @{Keys = "session"}
            }
            Logout = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/auth/signout"
                HttpMethod = "POST"
            }

        #endregion SESSION METHODS

        #region SERVER METHODS

            ServerInfo = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/serverinfo"
                HttpMethod = "GET"
                Response = @{Keys = "serverinfo"}
            }
            GetDomains = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/domains"
                HttpMethod = "GET"
                Response = @{Keys = "domainList"}
            }

        #endregion SERVER METHODS
        
        #region GROUP METHODS

            GetGroups = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/groups"
                HttpMethod = "GET"
                Response = @{Keys = "groups.group"}
            }
            AddGroupToSite = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/groups"
                HttpMethod = "POST"
                Body = "<tsRequest><group name='<0>'/></tsRequest>"
                Response = @{Keys = "group"}
            }
            RemoveGroupFromSite = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/groups/<0>"
                HttpMethod = "DELETE"
                Response = @{Keys = "group"}
            }
            GetGroupMembership = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/groups/<0>/users"
                HttpMethod = "GET"
                Response = @{Keys = "users.user"}
            }
            AddUserToGroup = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/groups/<0>/users"
                HttpMethod = "POST"
                Body = "<tsRequest><user id='<1>'/></tsRequest>"
                Response = @{Keys = "user"}
            }
            RemoveUserFromGroup = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/groups/<0>/users/<1>"
                HttpMethod = "DELETE"
                Response = @{Keys = ""}
            }

        #endregion GROUP METHODS

        #region SITE METHODS

            SwitchSite = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/auth/switchSite"
                HttpMethod = "POST"
                Body = "<tsRequest><site contentUrl='<0>'/></tsRequest>"
                Response = @{Keys = "credentials"}
            } 
            GetSites = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites"
                HttpMethod = "GET"
                Response = @{Keys = "sites.site"}
            }
            GetSite = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)"
                HttpMethod = "GET"
                Response = @{Keys = "site"}
            }

        #endregion SITE METHODS

        #region USER METHODS

            GetUsers = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/users"
                HttpMethod = "GET"
                Response = @{Keys = "users.user"}
            }
            GetUser = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/users/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "user"}
            }
            AddUser = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/users"
                HttpMethod = "POST"
                Body = "<tsRequest><user name='<0>' siteRole='<1>' /></tsRequest>"
                Response = @{Keys = "user"}
            }
            RemoveUser = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/users/<0>"
                HttpMethod = "DELETE"
                Response = @{Keys = ""}
            }
            UpdateUser = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/users/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><user fullName='<1>' email='<2>' siteRole='<3>' /></tsRequest>"
                Response = @{Keys = "user"}
            }
            UpdateUserPassword = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/users/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><user password='<1>' /></tsRequest>"
                Response = @{Keys = "user"}
            }
            GetUserMembership = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/users/<0>/groups"
                HttpMethod = "GET"
                Response = @{Keys = "groups.group"}
            }

        #endregion USER METHODS

        #region PROJECT METHODS 
            
            GetProjects = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/projects"
                HttpMethod = "GET"
                Response = @{Keys = "projects.project"}
            }
            GetProjectPermissions = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }
            GetProjectDefaultPermissions = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/default-permissions/<1>"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }
            AddProjectPermissions = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }
            AddProjectDefaultPermissions = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/default-permissions/<1>"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><2></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }
            RemoveProjectPermissions = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/permissions/<1>/<2>/<3>/<4>"
                HttpMethod = "DELETE"
                Response = @{Keys = "permissions"}
            }
            RemoveProjectDefaultPermissions = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/projects/<0>/default-permissions/<1>/<2>/<3>/<4>/<5>"
                HttpMethod = "DELETE"
                Response = @{Keys = "permissions"}
            }

        #endregion PROJECT METHODS

        #region WORKBOOK METHODS

            GetWorkbooks = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/workbooks"
                HttpMethod = "GET"
                Response = @{Keys = "workbooks.workbook"}
            }
            GetWorkbook = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "workbook"}
            }
            GetWorkbookPermissions = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }   
            AddWorkbookPermissions = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }

        #endregion WORKBOOK METHODS

        #region VIEW METHODS 

            GetViewsForSite = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/views"
                HttpMethod = "GET"
                Response = @{Keys = "views.view"}
            }
            GetViewsForWorkbook = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/workbooks/<0>/views"
                HttpMethod = "GET"
                Response = @{Keys = "views.view"}
            }

        #endregion VIEW METHODS 

        #region DATASOURCE METHODS 

            GetDataSources = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/datasources"
                HttpMethod = "GET"
                Response = @{Keys = "datasources.datasource"}
            }
            GetDatasourcePermissions = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>/permissions"
                HttpMethod = "GET"
                Response = @{Keys = "permissions"}
            }
            AddDataSourcePermissions = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/datasources/<0>/permissions"
                HttpMethod = "PUT"
                Body = "<tsRequest><permissions><granteeCapabilities><1></granteeCapabilities></permissions></tsRequest>"
                Response = @{Keys = "permissions"}
            }

        #endregion DATASOURCE METHODS


        #region FLOW METHODS

            GetFlows = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/flows"
                HttpMethod = "GET"
                Response = @{Keys = "flows.flow"}
            }

        #endregion FLOW METHODS          
        
        #region METRIC METHODS

            GetMetrics = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/metrics"
                HttpMethod = "GET"
                Response = @{Keys = "metrics.metric"}
            }

        #endregion METRIC METHODS              

        #region FAVORITE METHODS

            GetFavorites = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/favorites/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "favorites.favorite"}
            }
            AddFavorites = @{
                Path = "$($global:tsRestApiConfig.ApiUri)/sites/$($global:tsRestApiConfig.SiteId)/favorites/<0>"
                HttpMethod = "PUT"
                Body = "<tsRequest><favorite label='<1>'><<2> id='<3>'/></favorite></tsRequest>"
                Response = @{Keys = "favorites.favorite"}
            }

        #endregion FAVORITE METHODS
    

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
        $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
        # Write-Host+ $errorMessage -ForegroundColor DarkRed
        Write-Log -Message $errorMessage -EntryType "Error" -Action "TSRestApiMethod" -Target $Method -Status "Error"
        return $null, $null, $responseError
    }

    $responseRoot = "tsResponse"
    $pageFilter = "pageNumber=$($PageNumber)&pageSize=$($PageSize)"

    $filter = $FilterExpression ? "?filter=$($FilterExpression)&$($pageFilter)" : "?$($pageFilter)"

    $httpMethod = $global:tsRestApiConfig.Method.$Method.HttpMethod
    $path = "$($global:tsRestApiConfig.Method.$Method.Path)$($httpMethod -eq "GET" ? $filter : $null)"
    $body = $global:tsRestApiConfig.Method.$Method.Body 
    $headers = $global:tsRestApiConfig.Headers
    $keys = $global:tsRestApiConfig.Method.$Method.Response.Keys

    for ($i = 0; $i -lt $params.Count; $i++) {
        $path = $path -replace "<$($i)>",$Params[$i]
        $body = $body -replace "<$($i)>",$Params[$i]
        $keys = $keys -replace "<$($i)>",$Params[$i]
    }  
    
    try {
        $response = Invoke-RestMethod $path -Method $httpMethod -Headers $headers -Body $body -SkipCertificateCheck -SkipHttpErrorCheck -ContentType $global:tsRestApiConfig.ContentType -Verbose:$false 
    }
    catch {}

    $responseError = $response.$responseRoot.error

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

    $keys = $keys ? "$($responseRoot).$($keys)" : $responseRoot
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

#region SESSION

function global:Connect-TableauServer {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Server = "localhost",
        [Parameter(Mandatory=$false,Position=1)][string]$Site
    )

    Initialize-TSRestApiConfiguration $Server
    if ($Site) {Switch-TSSite $Site}

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

    $response,$pagination,$responseError = Invoke-TSRestApiMethod -Method Logout

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
        [switch][Alias("ResetCache")]$Update
    )

    if (!$Update) {
        if ($(get-cache platforminfo ).Exists()) {
            $platformInfo = Read-Cache platforminfo 
            if ($platformInfo) {
                $global:Platform.Version = $platformInfo.Version
                $global:Platform.Build = $platformInfo.Build
                $global:Platform.Api.TsRestApiVersion = $platformInfo.TsRestApiVersion
                return 
            }
        }
    }

    $response = Get-TSObjects -Method ServerInfo
    Write-Host+ -NoTrace -Iff (!$response) "Unable to connect to Tableau Server REST API." -ForegroundColor Red

    if ($response -and $Update) {
        $global:Platform.Api.TsRestApiVersion = $response.restApiVersion
        $global:Platform.Version = $response.productVersion.InnerText
        $global:Platform.Build = $response.productVersion.build
        Write-Cache platforminfo -InputObject @{Version=$global:Platform.Version;Build=$global:Platform.Build;TsRestApiVersion=$global:Platform.Api.TsRestApiVersion}
    }

    return $response

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
        [Parameter(Mandatory=$false)][string]$FilterExpression
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $objects = @()

    $pageNumber = 1
    $pageSize = 100

    do {
        $response,$pagination,$responseError = Invoke-TSRestApiMethod -Method $Method -Params $Params -FilterExpression $FilterExpression -PageNumber $pageNumber -PageSize $pageSize
        if ($responseError.code -eq "401002") {
            $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
            Write-Host+ $errorMessage -ForegroundColor DarkRed
            Write-Log -Message $errorMessage -EntryType "Error" -Action $Method -Status "Error"
            return
        }
        $objects += $response
        $pagenumber += 1
    } until ($pagination.IsLastPage)

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
        [Parameter(Mandatory=$false,Position=0)][string]$Site = ""
    )

    if ($Site -notin (Get-TSSites).contentUrl) {    
        
        $message = "Site '$($Site)' is not a valid contentURL for a site on $($global:tsRestApiConfig.Server)"
        Write-Host+ $message -ForegroundColor DarkRed
        Disconnect-TableauServer

        $message = "You must reconnect to Tableau Server to continue."
        Write-Host+ $message -ForegroundColor DarkYellow
        Write-Log -Message $message -EntryType "Error" -Action "SwitchSite" -Target $Site -Status "Error"
        
        return
    }

    if ($Site -eq $global:tsRestApiConfig.ContentUrl) {return}

    $response,$pagination,$responseError = Invoke-TSRestApiMethod -Method "SwitchSite" -Params @($Site)
    if ($responseError) {
        $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
        Write-Host+ -NoTrace $errorMessage -ForegroundColor DarkRed
        Write-Log -Message $errorMessage -EntryType "Error" -Action "SwitchSite" -Status "Error"
        return
    }

    $global:tsRestApiConfig.Token = $response.token
    $global:tsRestApiConfig.SiteId = $response.site.id
    $global:tsRestApiConfig.ContentUrl = $response.site.contentUrl
    $global:tsRestApiConfig.UserId = $response.user.id 
    $global:tsRestApiConfig.Headers = @{"Content-Type" = $global:tsRestApiConfig.ContentType; "X-Tableau-Auth" = $global:tsRestApiConfig.Token}

    Update-TSRestApiMethods

    return
}

function global:Get-TSSites {

    [CmdletBinding()]
    param()

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    return Get-TSObjects -Method GetSites
}

function global:Get-TSSite {

    [CmdletBinding()]
    param()

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    return Get-TSObjects -Method GetSite
}

function global:Get-TSCurrentSite {

    [CmdletBinding()]
    param()

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

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

function global:Get-TSUsers {

    [CmdletBinding()]
    param()

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    return Get-TSObjects -Method GetUsers
}

function global:Get-TSUser {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false,Position=0)][string]$Id = ((Get-TSCurrentUser).id)
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
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
        [Parameter(Mandatory=$true)][string]$FullName,
        [Parameter(Mandatory=$true)][string]$Email,
        [Parameter(Mandatory=$false)][string]$SiteRole
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    if ([string]::IsNullOrEmpty($FullName)) {
        $errorMessage = "$($Site.contentUrl)\$($tsSiteUser.name) : FullName is missing or invalid."
        Write-Log -Message $errorMessage.Split(":")[1].Trim() -EntryType "Error" -Action "AddUser" -Target "$($Site.contentUrl)\$($tsSiteUser.name)" -Status "Error" 
        Write-Host+ "      $errorMessage" -ForegroundColor DarkRed
        return
    }
    if ([string]::IsNullOrEmpty($Email)) {
        $errorMessage = "$($Site.contentUrl)\$($tsSiteUser.name) : Email is missing or invalid."
        Write-Log -Message $errorMessage.Split(":")[1].Trim() -EntryType "Error" -Action "AddUser" -Target "$($Site.contentUrl)\$($tsSiteUser.name)" -Status "Error" 
        Write-Host+ "      $errorMessage" -ForegroundColor DarkRed
        return
    }

    $SiteRole = $SiteRole -in $global:SiteRoles ? $SiteRole : "Unlicensed"

    # $response is a user object or an error object
    $response,$pagination,$responseError = Invoke-TSRestApiMethod -Method "AddUser" -Params @($Username,$SiteRole)
    if ($responseError.code -eq "401002") {
        $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
        Write-Host+ $errorMessage -ForegroundColor DarkRed
        Write-Log -Message $errorMessage -EntryType "Error" -Action "AddUser" -Status "Error"
        return
    }
    elseif ($responseError) {
        # $response is an error object
        $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
        Write-Log -Action "AddUser" -Target "$($global:tsRestApiConfig.ContentUrl)\$($Username)" -Status "Error" -Message $errorMessage -EntryType "Error"
        Write-Host+ "      $($response.error.detail)" -ForegroundColor DarkRed
    }
    else {
        $tsSiteUser = $response # $response is a user object
        Write-Log -Action "AddUser" -Target "$($Site.contentUrl)\$($tsSiteUser.name)" -Force 
        
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
    if ($FullName -ne $User.fullname) {$update += "$($update ? " | " : $null)$($User.fullname ? "$($User.fullname) > " : $null)$($FullName)"}
    if ($Email -ne $User.name) {$update += "$($update ? " | " : $null)$($User.name ? "$($User.name) > " : $null)$($Email)"}
    if ($SiteRole -ne $User.siteRole) {$update += "$($update ? " | " : $null)$($User.siteRole ? "$($User.siteRole) > " : $null)$($SiteRole)"}

    $FullName = $FullName ? $FullName : $User.fullName
    $Email = $Email ? $Email : $User.Name

    # apostrophes and xml don't mix, so replace both apostrophe characters with "&apos;""
    $FullName = $FullName.replace("'","&apos;").replace("’","&apos;")
    $Email = $Email.replace("'","&apos;").replace("’","&apos;")

    $SiteRole = $SiteRole -in $global:SiteRoles ? $SiteRole : $User.SiteRole
    
    # $response is an update object (NOT a user object) or an error object
    $response,$pagination,$responseError = Invoke-TSRestApiMethod -Method "UpdateUser" -Params @($User.Id,$FullName,$Email,$SiteRole)
    if ($responseError.code -eq "401002") {
        $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
        Write-Host+ $errorMessage -ForegroundColor DarkRed
        Write-Log -Message $errorMessage -EntryType "Error" -Action $action -Status "Error"
        # return
    }
    elseif ($responseError) {
        # $response is an an error object
        $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
        Write-Log -Action $action -Target "$($global:tsRestApiConfig.ContentUrl)\$($User.name)" -Status "Error" -Message $errorMessage -EntryType "Error"
        Write-Host+ "      $($response.error.detail)" -ForegroundColor DarkRed
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
    $response,$pagination,$responseError = Invoke-TSRestApiMethod -Method "UpdateUserPassword" -Params @($User.id,$Password)
    if ($responseError.code -eq "401002") {
        $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
        Write-Host+ $errorMessage -ForegroundColor DarkRed
        Write-Log -Message $errorMessage -EntryType "Error" -Action "UpdateUserPassword" -Status "Error"
        return
    }
    elseif ($responseError) {
        # $response is an an error object
        $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
        Write-Log -Action "UpdateUserPassword" -Target "$($global:tsRestApiConfig.ContentUrl)\$($User.name)" -Status "Error" -Message $errorMessage -EntryType "Error"
        Write-Host+ "      $($response.error.detail)" -ForegroundColor DarkRed
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
    if ($responseError.code -eq "401002") {
        $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
        Write-Host+ $errorMessage -ForegroundColor DarkRed
        Write-Log -Message $errorMessage -EntryType "Error" -Action "RemoveUser" -Status "Error"
        # return
    }
    elseif ($responseError) {
        # $response is an an error object
        $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
        Write-Log -Action "RemoveUser" -Target "$($global:tsRestApiConfig.ContentUrl)\$($User.name)" -Status "Error" -Message $errorMessage -EntryType "Error"
        Write-Host+ "      $($response.error.detail)" -ForegroundColor DarkRed
    }
    else {
        Write-Log -Action "RemoveUser" -Target "$($global:tsRestApiConfig.ContentUrl)\$($User.name)" -Force 
    }

    return $response, $responseError

} 
Set-Alias -Name Remove-TSUserFromSite -Value Remove-TSUser -Scope Global

#endregion USERS

#region GROUPS

function global:Get-TSGroups {

    [CmdletBinding()]
    param()

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

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
        $response,$pagination,$responseError = Invoke-TSRestApiMethod -Method "AddUserToGroup" -Params @($Group.Id,$_.Id)
        if ($responseError.code -eq "401002") {
            $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
            Write-Host+  $errorMessage -ForegroundColor DarkRed
            Write-Log -Message $errorMessage -EntryType "Error" -Action "AddUserToGroup" -Status "Error"
            return
        }
        elseif ($responseError) {
            $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
            Write-Log -Action "AddUserToGroup" -Target "$($global:tsRestApiConfig.ContentUrl)\$($Group.name)\$($_.Name)" -Status "Error" -Message $errorMessage -EntryType "Error"
            Write-Host+ "      $($response.error.detail)" -ForegroundColor DarkRed
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
        $response,$pagination,$responseError = Invoke-TSRestApiMethod -Method "RemoveUserFromGroup" -Params @($Group.Id,$_.Id)
        if ($responseError.code -eq "401002") {
            $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
            Write-Host+ $errorMessage -ForegroundColor DarkRed
            Write-Log -Message $errorMessage -EntryType "Error" -Action "RemoveUserFromGroup" -Status "Error"
            return
        }
        elseif ($responseError) {
            $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
            Write-Log -Action "RemoveUserFromGroup" -Target "$($global:tsRestApiConfig.ContentUrl)\$($Group.name)\$($_.Name)" -Status "Error" -Message $errorMessage -EntryType "Error"
            Write-Host+ "      $($response.error.detail)" -ForegroundColor DarkRed
        }
        else {
            # $usersRemovedFromGroup += 1
            # Write-Log -Action "RemoveUserFromGroup" -Target "$($global:tsRestApiConfig.ContentUrl)\$($Group.name)\$($_.Name)" -Status "-$($usersRemovedFromGroup)" -Force
            Write-Log -Action "RemoveUserFromGroup" -Target "$($global:tsRestApiConfig.ContentUrl)\$($Group.name)\$($_.Name)" -Force
        }
    }

    return
}   

#endregion GROUPS

#region PROJECTS

function global:Get-TSProjects+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers)
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    $projects = @()
    Get-TSProjects | ForEach-Object {
        $project = @{}
        $projectMembers = $_ | Get-Member -MemberType Property
        foreach ($member in  $projectMembers) {
            $project.($member.Name) = $_.($member.Name)
        }
        $project.owner = Find-TSUser -Users $Users -Id $_.owner.id
        $projects += $project
    }

    return $projects
}

function global:Get-TSProjects {

    [CmdletBinding()]
    param()

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
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

    $message = "Getting project permissions : PENDING"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 38 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

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
    $message = "$($emptyString.PadLeft(8,"`b")) $($projectPermissionsCount)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

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

    $response,$pagination,$responseError = Invoke-TSRestApiMethod -Method AddProjectPermissions -Params @($Project.id,$capabilityXML)
    if ($responseError.code -eq "401002") {
        $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
        Write-Host+ $errorMessage -ForegroundColor DarkRed
        Write-Log -Message $errorMessage -EntryType "Error" -Action "AddProjectPermissions" -Status "Error"
        # return
    }
    
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
        $response,$pagination,$responseError = Invoke-TSRestApiMethod -Method "RemoveProjectPermissions" -Params @($Project.id,$granteeType,$grantee.Id,$capabilityName,$capabilityMode)
        if ($responseError.code -eq "401002") {
            $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
            Write-Host+ $errorMessage -ForegroundColor DarkRed
            Write-Log -Message $errorMessage -EntryType "Error" -Action "RemoveProjectPermissions" -Status "Error"
            # return
        }
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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $validateSetWorkbooks = @(
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
        "Write:Allow","Write:Deny"
    )

    $validateSetDataSources = @(
        "ChangePermissions:Allow","ChangePermissions:Deny",
        "Connect:Allow","Connect:Deny",
        "Delete:Allow","Delete:Deny",
        "ExportXml:Allow","ExportXml:Deny",
        "Read:Allow","Read:Deny",
        "Write:Allow","Write:Deny"
    )

    $validateSetFlows = @(
        "Read:Allow","Read:Deny",
        "ExportXml:Allow","ExportXml:Deny",
        "Run:Allow","Run:Deny",
        "Write:Allow","Write:Deny",
        "WebAuthoring:Allow","WebAuthoring:Deny",
        "Move:Allow","Move:Deny",
        "Delete:Allow","Delete:Deny",
        "ChangePermissions:Allow","ChangePermissions:Deny"
    )

    $validateSetMetrics = @(
        "Read:Allow","Read:Deny",
        "Write:Allow","Write:Deny",
        "Move:Allow","Move:Deny",
        "Delete:Allow","Delete:Deny",
        "ChangePermissions:Allow","ChangePermissions:Deny"
    )   
    
    # $validateSetDataRoles = @(
    #     "Read:Allow","Read:Deny",
    #     "Write:Allow","Write:Deny",
    #     "Move:Allow","Move:Deny",
    #     "Delete:Allow","Delete:Deny",
    #     "ChangePermissions:Allow","ChangePermissions:Deny"
    # )  

    switch ($Type) {
        "Workbooks" {
            $Capabilities | Foreach-Object {
                if ($_ -notin $validateSetWorkbooks) {
                    throw "$($_) is not a valid capability"
                }
            }
        }
        "Datasources" {
            $Capabilities | Foreach-Object {
                if ($_ -notin $validateSetDatasources) {
                    throw "$($_) is not a valid capability"
                }
            }
        }
        "Flows" {
            $Capabilities | Foreach-Object {
                if ($_ -notin $validateSetFlows) {
                    throw "$($_) is not a valid capability"
                }
            }
        }
        "Metrics" {
            $Capabilities | Foreach-Object {
                if ($_ -notin $validateSetMetrics) {
                    throw "$($_) is not a valid capability"
                }
            }
        }
        # "DataRoles" {
        #     $Capabilities | Foreach-Object {
        #         if ($_ -notin $validateSetDataRoles) {
        #             throw "$($_) is not a valid capability"
        #         }
        #     }
        # }
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

    $response,$pagination,$responseError = Invoke-TSRestApiMethod -Method "AddProjectDefaultPermissions" -Params @($Project.id,$Type,$capabilityXML)
    if ($responseError.code -eq "401002") {
        $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
        Write-Host+ $errorMessage -ForegroundColor DarkRed
        Write-Log -Message $errorMessage -EntryType "Error" -Action "AddProjectDefaultPermissions" -Status "Error"
        # return
    }
    
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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $validateSetWorkbooks = @(
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
        "Write:Allow","Write:Deny"
    )

    $validateSetDataSources = @(
        "ChangePermissions:Allow","ChangePermissions:Deny",
        "Connect:Allow","Connect:Deny",
        "Delete:Allow","Delete:Deny",
        "ExportXml:Allow","ExportXml:Deny",
        "Read:Allow","Read:Deny",
        "Write:Allow","Write:Deny"
    )

    switch ($Type) {
        "Workbooks" {
            $Capabilities | Foreach-Object {
                if ($_ -notin $validateSetWorkbooks) {
                    throw "$($_) is not a valid capability"
                }
            }
        }
        "Datasources" {
            $Capabilities | Foreach-Object {
                if ($_ -notin $validateSetDatasources) {
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
        $response,$pagination,$responseError = Invoke-TSRestApiMethod -Method "RemoveProjectDefaultPermissions" -Params @($Project.id,$Type,$granteeType,$grantee.Id,$capabilityName,$capabilityMode)
        if ($responseError.code -eq "401002") {
            $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
            Write-Host+ $errorMessage -ForegroundColor DarkRed
            Write-Log -Message $errorMessage -EntryType "Error" -Action "RemoveProjectDefaultPermissions" -Status "Error"
            # return
        }
    }
    
    return $response,$responseError
}

#endregion PROJECTS

#region WORKBOOKS

function global:Get-TSWorkbooks+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers),
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+)
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    $workbooks = @()
    Get-TSWorkbooks | ForEach-Object {
        $workbook = @{}
        $workbookMembers = $_ | Get-Member -MemberType Property
        foreach ($member in  $workbookMembers) {
            $workbook.($member.Name) = $_.($member.Name)
        }
        $workbook.owner = Find-TSUser -Users $Users -Id $_.owner.id
        $workbook.project = Find-TSProject -Projects $Projects -Id $_.project.id
        $workbooks += $workbook
    }

    return $workbooks
}

function global:Get-TSWorkbooks {

    [CmdletBinding()]
    param()

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    return Get-TSObjects -Method GetWorkbooks
}

function global:Get-TSWorkbook {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    return Get-TSObjects -Method GetWorkbook -Params @($Id)
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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    return Get-TSObjects -Method GetWorkbookPermissions -Params @($Workbook.Id)
}

function global:Add-TSWorkbookPermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Workbook,
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        [Parameter(Mandatory=$false)]
        [ValidateSet(
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
            "Write:Allow","Write:Deny"      
        )]
        [string[]]
        $Capabilities 
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

    $response,$pagination,$responseError = Invoke-TSRestApiMethod -Method "AddWorkBookPermissions" -Params @($Workbook.id,$capabilityXML)
    if ($responseError.code -eq "401002") {
        $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
        Write-Host+ $errorMessage -ForegroundColor DarkRed
        Write-Log -Message $errorMessage -EntryType "Error" -Action "AddWorkBookPermissions" -Status "Error"
        # return
    }
    
    return $response,$responseError
}

#endregion WORKBOOKS

#region VIEWS

function global:Get-TSViews+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers),
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+),
        [Parameter(Mandatory=$false)][object]$Workbooks = (Get-TSWorkbooks+)
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    $views = @()
    Get-TSViews | ForEach-Object {
        $view = @{}
        $viewMembers = $_ | Get-Member -MemberType Property
        foreach ($member in  $viewMembers) {
            $view.($member.Name) = $_.($member.Name)
        }
        $view.owner = Find-TSUser -Users $Users -Id $_.owner.id
        $view.project = Find-TSProject -Projects $Projects -Id $_.project.id
        $view.workbook = Find-TSWorkbook -Workbooks $Workbooks -Id $_.workbook.id
        $views += $view
    }

    return $views
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

#endregion VIEWS

#region DATASOURCES

function global:Get-TSDatasources+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][object]$Users = (Get-TSUsers),
        [Parameter(Mandatory=$false)][object]$Projects = (Get-TSProjects+)
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    $datasources = @()
    Get-TSDatasources | ForEach-Object {
        $datasource = @{}
        $datasourceMembers = $_ | Get-Member -MemberType Property
        foreach ($member in  $datasourceMembers) {
            $datasource.($member.Name) = $_.($member.Name)
        }
        $datasource.owner = Find-TSUser -Users $Users -Id $_.owner.id
        $datasource.project = Find-TSProject -Projects $Projects -Id $_.project.id
        $datasources += $datasource
    }

    return $datasources
}

function global:Get-TSDataSources {

    [CmdletBinding()]
    param()

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    return Get-TSObjects -Method GetDataSources
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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    return Get-TSObjects -Method GetDatasourcePermissions -Params @($Datasource.Id)
}

function global:Add-TSDataSourcePermissions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$DataSource,
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        [Parameter(Mandatory=$false)][ValidateSet("ChangePermissions:Allow","Connect:Allow","Delete:Allow","ExportXml:Allow","Read:Allow","Write:Allow")][string[]]$Capabilities 
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

    $response,$pagination,$responseError = Invoke-TSRestApiMethod -Method "AddDataSourcePermissions" -Params @($DataSource.id,$capabilityXML)
    if ($responseError.code -eq "401002") {
        $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
        Write-Host+ $errorMessage -ForegroundColor DarkRed
        Write-Log -Message $errorMessage -EntryType "Error" -Action "AddDataSourcePermissions" -Status "Error"
        # return
    }
    
    return $response,$responseError
}

#endregion DATASOURCES

#region FLOWS

function global:Get-TSFlows {

    [CmdletBinding()]
    param()

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    return Get-TSObjects -Method GetFlows
}

#endregion FLOWS

#region METRICS

function global:Get-TSMetrics {

    [CmdletBinding()]
    param()

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    return Get-TSObjects -Method GetMetrics
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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
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
            $errorMessage = "Error adding favorite:  $($favorite.user.name)  $($favorite.label)  $($favorite.favoriteType)  $($favorite.($favorite.favoriteType).name)"
            Write-Host+ $errorMessage -ForegroundColor DarkRed
            Write-Log -Message $errorMessage -EntryType "Error" -Action "AddFavorites" -Status "Error"
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

    $response,$pagination,$responseError = Invoke-TSRestApiMethod -Method "AddFavorites" -Params @($User.id,($Label.replace("&","&amp;")),$Type,$InputObject.id)
    if ($responseError.code) {
        $errorMessage = "$($responseError.detail)\$($responseError.summary)\$($responseError.code)"
        Write-Host+ $errorMessage -ForegroundColor DarkRed
        Write-Log -Message $errorMessage -EntryType "Error" -Action "AddFavorites" -Status "Error"
        return
    }
    
    return $response,$responseError
}

#endregion FAVORITES

#region SYNC

function global:Sync-TSGroups {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [switch]$Delta
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $emptyString = ""
    $startTime = Get-Date -AsUTC

    $lastStartTime = (Read-Cache "AzureADSyncGroups").LastStartTime ?? [datetime]::MinValue

    $message = "Getting Azure AD groups and users"
    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor Gray

    $message = "  Group updates : PENDING"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

    $azureADGroupUpdates,$cacheError = Get-AzureADGroups -Tenant $Tenant -AsArray -After $lastStartTime
    if ($cacheError) {
        Write-Log -Context "AzureADSync" -Action ($Delta ? "Update" : "Get") -Target "Groups" -Status $cacheError.code -Message $cacheError.summary -EntryType "Error"
        $message = "$($emptyString.PadLeft(8,"`b")) ERROR$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkRed
        $message = "    Error $($cacheError.code) : ($($cacheError.summary)))"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkRed
        return
    }
    
    $message = "$($emptyString.PadLeft(8,"`b")) $($azureADGroupUpdates.Count)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen

    $message = "  Groups : PENDING"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

    $azureADGroups,$cacheError = Get-AzureADGroups -Tenant $Tenant -AsArray
    if ($cacheError) {
        Write-Log -Context "AzureADSync" -Action ($Delta ? "Update" : "Get") -Target "Groups" -Status $cacheError.code -Message $cacheError.summary -EntryType "Error"
        $message = "$($emptyString.PadLeft(8,"`b")) ERROR$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message -ForegroundColor DarkRed
        $message = "    Error $($cacheError.code) : ($($cacheError.summary)))"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkRed
        return
    }

    if ($azureADGroups.Count -le 0) {
        $message = "$($emptyString.PadLeft(8,"`b")) ($Delta ? 'SUCCESS' : 'CACHE EMPTY')$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message -ForegroundColor ($Delta ? "DarkGreen" : "DarkRed")
        Write-Host+
        return
    }

    $message = "$($emptyString.PadLeft(8,"`b")) $($azureADGroups.Count)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    
    $message = "  Users : PENDING"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

    $azureADUsers,$cacheError = Get-AzureADUsers -Tenant $Tenant -AsArray
    if ($cacheError) {
        Write-Log -Context "AzureADSync" -Action ($Delta ? "Update" : "Get") -Target "Users" -Status $cacheError.code -Message $cacheError.summary -EntryType "Error"
        $message = "$($emptyString.PadLeft(8,"`b")) ERROR$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkRed
        $message = "    Error $($cacheError.code) : ($($cacheError.summary)))"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkRed
        return
    }

    if ($azureADUsers.Count -le 0) {
        $message = "$($emptyString.PadLeft(8,"`b")) ($Delta ? 'SUCCESS' : 'CACHE EMPTY')$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message -ForegroundColor ($Delta ? "DarkGreen" : "DarkRed")
        Write-Host+
        return
    }

    $message = "$($emptyString.PadLeft(8,"`b")) $($azureADUsers.Count)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

    Write-Host+
    $message = "Syncing Tableau Server groups : PENDING"
    Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

    foreach ($contentUrl in $global:AzureADSync.Sites.ContentUrl) {

        Switch-TSSite $contentUrl
        $tsSite = Get-TSSite
        Write-Host+ -NoTrace "  Site: $($tsSite.name)"

        $tsGroups = Get-TSGroups | Where-Object {$_.name -in $azureADGroups.displayName -and $_.name -notin $global:tsRestApiConfig.SpecialGroups} | Select-Object -Property *, @{Name="site";Expression={$null}} | Sort-Object -Property name
        $tsUsers = Get-TSUsers | Sort-Object -Property name

        foreach ($tsGroup in $tsGroups) {

            Write-Host+ -NoTrace -NoNewLine "    Group: $($tsGroup.name)"

            $azureADGroupToSync = $azureADGroups | Where-Object {$_.displayName -eq $tsGroup.name}
            $tsGroupMembership = Get-TSGroupMembership -Group $tsGroup
            $azureADGroupMembership = $azureADUsers | Where-Object {$_.id -in $azureADGroupToSync.members -and $_.accountEnabled}

            $tsUsersToAddToGroup = ($tsUsers | Where-Object {$_.name -in $azureADGroupMembership.userPrincipalName -and $_.id -notin $tsGroupMembership.id}) ?? @()
            $tsUsersToRemoveFromGroup = $tsGroupMembership | Where-object {$_.name -notin $azureADGroupMembership.userPrincipalName}

            $newUsers = @()
            $azureADUsersToAddToSite = $azureADGroupMembership | Where-Object {$_.userPrincipalName -notin $tsUsers.name} | Sort-Object -Property userPrincipalName
            foreach ($azureADUser in $azureADUsersToAddToSite) {

                # validate Azure AD email address
                # if Azure AD email address fails validation and user is an Azure AD guest, convert upn into email address
                $azureADUserMail = $azureADUser.mail -match $global:RegexPattern.Mail ? $Matches[0] : $azureADUser.userPrincipalName -match $global:RegexPattern.Mail ? $Matches[0] : ($azureADUser.userPrincipalName -match $global:RegexPattern.AzureAD.MailFromGuestUserUPN.Match ? $global:RegexPattern.AzureAD.MailFromGuestUserUPN.Substitution : $null)

                $params = @{
                    Site = $tsSite
                    Username = $azureADUser.userPrincipalName
                    FullName = $azureADUser.displayName
                    Email = $azureADUserMail
                    SiteRole = $tsGroup.import.siteRole ?? "Explorer"
                }

                $newUser = Add-TSUserToSite @params
                $newUsers += $newUser

            }

            if ($azureADUsersToAddToSite) {
                # force a reindex after creating users so group updates work
                $reindexSearch = Invoke-TsmApiMethod -Method "ReindexSearch"
                $reindexSearch,$timeout = Wait-Asyncjob -id $reindexSearch.id -IntervalSeconds 5 -TimeoutSeconds 60
                if ($timeout) {
                    Write-Log -Context "AzureADSync" -Action "ReindexSearch" -Target "$($tsSite.contentUrl)\$($tsGroup.name)" -Status "Timeout" -Force 
                }
                else {
                    Write-Log -Context "AzureADSync" -Action "ReindexSearch" -Target "$($tsSite.contentUrl)\$($tsGroup.name)" -Message "TotalMilliSeconds = $($reindexSearch.completedAt -$reindexSearch.createdAt)" -Force
                }
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
                Write-Host+ -NoTrace -NoNewLine -NoTimeStamp "  -$($tsUsersToRemoveFromGroup.count) users" -ForegroundColor DarkRed
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
        Write-Log -Context "AzureADSync" -Action ($Delta ? "Update" : "Get") -Target "Users" -Status $cacheError.code -Message $cacheError.summary -EntryType "Error"
        $message = "  $($emptyString.PadLeft(8,"`b")) ERROR$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkRed
        $message = "    Error $($cacheError.code) : ($($cacheError.summary)))"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkRed
        return
    }

    $message = "$($emptyString.PadLeft(8,"`b")) $($azureADUsers.Count)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

    if ($azureADUsers.Count -le 0) {
        Write-Host+
        $message = "Syncing Tableau Server users : $($Delta ? 'SUCCESS' : 'CACHE EMPTY')"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,($Delta ? "DarkGreen" : "DarkRed")
        Write-Host+
        return
    }

    Write-Host+
    $message = "Syncing Tableau Server users : PENDING"
    Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

    foreach ($contentUrl in $global:AzureADSync.Sites.ContentUrl) {

        Switch-TSSite $contentUrl
        $tsSite = Get-TSSite

        [console]::CursorVisible = $false

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
                $siteRole = "ExplorerCanPublish"
            }
            else {
                $siteRole = $tsUser.siteRole
            }

            # if the users' Azure AD account has been disabled and they're not in an admin role, set them to unlicensed
            # ignore users that are already unlicensed
            # TODO: remove unlicensed users from their groups? 

            if ($tsUser.siteRole -notin $global:SiteAdminRoles -and !$azureADUser.accountEnabled) {

                if ($tsUser.SiteRole -ne "Unlicensed") {

                    $response, $responseError = Update-TSUser -User $tsUser -SiteRole "Unlicensed" | Out-Null
                    if ($responseError) {
                        Write-Log -Context "AzureADSync" -Action "DisableUser" -Target "$($tsSite.contentUrl)\$($tsUser.name)" -Message "$($responseError.detail)" -EntryType "Error"
                        Write-Host+ "      $($response.error.detail)" -ForegroundColor DarkRed
                    }
                    else {
                        # Write-Log -Context "AzureADSync" -Action "DisableUser" -Target "$($tsSite.contentUrl)\$($tsUser.name)" -Message "$siteRole" -EntryType "Information" -Force
                        Write-Host+ -NoTrace "      Disable: $($tsUser.id) $($tsUser.name): $($tsUser.siteRole) >> $siteRole" -ForegroundColor DarkRed
                    }

                    $lastOp = "Disable"

                }

            }
            
            # Update-tsUser replaces both apostrophe characters ("'" and "’") in fullName and email with "&apos;" (which translates to "'")
            # Replace "’" with "'" in order to correctly compare fullName and email from $tsUser and $azureADUser 
            
            elseif ($fullName.replace("’","'") -ne $tsUser.fullName -or $email.replace("’","'") -ne $tsUser.email -or $siteRole -ne $tsUser.siteRole) {
                $response, $responseError = Update-tsUser -User $tsUser -FullName $fullName -Email $email -SiteRole $siteRole | Out-Null
                if ($responseError) {
                    Write-Log -Context "AzureADSync" -Action "UpdateUser" -Target "$($tsSite.contentUrl)\$($tsUser.name)" -Message "$($responseError.detail)" -EntryType "Error"
                    Write-Host+ "      $($response.error.detail)" -ForegroundColor DarkRed
                }
                else {
                    # Write-Log -Context "AzureADSync" -Action "UpdateUser" -Target "$($tsSite.contentUrl)\$($tsUser.name)" -Message "$fullName | $email | $siteRole" -EntryType "Information" -Force
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