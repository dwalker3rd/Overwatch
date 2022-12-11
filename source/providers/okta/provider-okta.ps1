function global:Initialize-OktaRestApiConfiguration {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Domain,
        [switch]$Reinitialization
    )

    if ($Reinitialization) {
        $global:OktaRestApiConfig = @{}
    }

    $global:OktaRestApiConfig = @{
        Credentials = $Domain
        Domain = $Domain
        Headers = @{
            "Accept" = "application/json"
            "Content-Type" = "application/json"
            "Authorization" = "SSWS <Api.Key>"
        }        
    }

    $global:OktaRestApiConfig.Api = @{
        EndPoint = "/api"
        Key = $(Get-Credentials $global:OktaRestApiConfig.Credentials).GetNetworkCredential().Password
        Uri = ""
        Version = "v1"
    }
    $global:OktaRestApiConfig.Api.Uri = 
        "https://$($global:OktaRestApiConfig.Domain)$($global:OktaRestApiConfig.Api.EndPoint)/$($global:OktaRestApiConfig.Api.Version)"

    $global:OktaRestApiConfig.View = @{
        User = @(
            "id", "status", 
            @{Name="created";Expression={$_.created.ToString('u')}}, 
            @{Name="activated";Expression={$_.activated.ToString('u')}}, 
            @{Name="statusChanged";Expression={$_.statusChanged.ToString('u')}},
            @{Name="lastLogin";Expression={$_.lastLogin.ToString('u')}},
            @{Name="lastUpdated";Expression={$_.lastUpdated.ToString('u')}},
            @{Name="passwordChanged";Expression={$_.passwordChanged.ToString('u')}}, 
            "type", "profile", "credentials", "_links"
        )
        Group = @(
            "id", 
            @{Name="created";Expression={$_.created.ToString('u')}}, 
            @{Name="lastUpdated";Expression={$_.lastUpdated.ToString('u')}},
            @{Name="lastMembershipUpdated";Expression={$_.lastMembershipUpdated.ToString('u')}},
            "objectClass","type", "profile", "source", "_links"
        )
    }

    $global:OktaRestApiConfig.Method = @{
        GetGroups = @{
            Uri = "$($global:OktaRestApiConfig.Api.Uri)/groups"
            HttpMethod = "GET"
            View = "Group"
        }
        GetGroup = @{
            Uri = "$($global:OktaRestApiConfig.Api.Uri)/groups/<0>"
            HttpMethod = "GET"
            View = "Group"
        }
        GetGroupMembership = @{
            Uri = "$($global:OktaRestApiConfig.Api.Uri)/groups/<0>/users"
            HttpMethod = "GET"
            View = "Group"
        }
        GetUsers = @{
            Uri = "$($global:OktaRestApiConfig.Api.Uri)/users"
            HttpMethod = "GET"
            View = "User"
        }
        GetUser = @{
            Uri = "$($global:OktaRestApiConfig.Api.Uri)/users/<0>"
            HttpMethod = "GET"
            View = "User"
        }
        GetUserMembership = @{
            Uri = "$($global:OktaRestApiConfig.Api.Uri)/users/<0>/groups"
            HttpMethod = "GET"
            View = "User"
        }
    }
}
Set-Alias -Name oktaRestApiInit -Value Initialize-OktaRestApiConfiguration -Scope Global

function global:Invoke-OktaRestApiMethod {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Method,
        [Parameter(Mandatory=$false,Position=1)][string[]]$Params,
        [Parameter(Mandatory=$false)][ValidateRange(1,1000)][int]$Limit = 200,
        [Parameter(Mandatory=$false)][string]$Filter,
        [Parameter(Mandatory=$false)][string]$Search,
        [Parameter(Mandatory=$false)][int]$TimeoutSec = 0
    )

    $responseRoot = $null

    $limitFilter = "limit=$($Limit)"
    $_filter = $Filter ? "filter=$([System.Web.HttpUtility]::UrlEncode($Filter))&$($limitFilter)" : "$($limitFilter)"
    $_search = $Search ? "search=$([System.Web.HttpUtility]::UrlEncode($Search))&$($limitFilter)" : "$($limitFilter)"

    $httpMethod = $global:OktaRestApiConfig.Method.$Method.HttpMethod

    $uri = "$($global:OktaRestApiConfig.Method.$Method.Uri)"
    $questionMarkOrAmpersand = $uri.Contains("?") ? "&" : "?"
    $uri += ![string]::IsNullOrEmpty($_search) ? "$($questionMarkOrAmpersand)$($_search)" : "$($questionMarkOrAmpersand)$($_filter)"

    $body = $global:OktaRestApiConfig.Method.$Method.Body
    
    $creds = Get-Credentials $global:OktaRestApiConfig.Credentials

    $headers = $global:OktaRestApiConfig.Headers | Copy-Object
    foreach ($key in $global:OktaRestApiConfig.Method.$Method.Headers.Keys) {
        if ($key -in $headers.Keys) { $headers.Remove($key) }
        $headers.$key = $global:OktaRestApiConfig.Method.$Method.Headers.$key
    }
    $headers."Authorization" = $headers."Authorization".Replace("<Api.Key>",$creds.GetNetworkCredential().Password)

    for ($i = 0; $i -lt $Params.Count; $i++) {
        $uri = $uri -replace "<$($i)>",$Params[$i]
        $body = $body -replace "<$($i)>",$Params[$i]
        $keys = $keys -replace "<$($i)>",$Params[$i]
    } 
    
    if ($headers.ContentLength) { $headers.ContentLength = $body.Length }
    
    $response = @()
    do {

        $response += Invoke-RestMethod -Uri $uri -Method $httpMethod -Headers $headers -Body $body -TimeoutSec $TimeoutSec -SkipCertificateCheck -SkipHttpErrorCheck -Verbose:$false -ResponseHeadersVariable responseHeaders -StatusCodeVariable httpStatusCode

        $uri = $null
        if ($httpStatusCode -eq "200") {
            if ($responseHeaders.Link) {
                $nextLink = $responseHeaders.Link | Where-Object {$_.EndsWith('rel="next"')}
                if ($nextLink) {
                    $uri = $nextLink.ToString() -match "^<(.*)>; rel=`"next`"`$" ? $Matches[1] : $null
                }
            }
        }

        Write-Host+ -NoTrace -NoTimestamp $uri -ForegroundColor DarkGray

    } until ([string]::IsNullOrEmpty($uri))

    $keys = $keys ? "$($responseRoot)$($responseRoot ? "." : $null)$($keys)" : $responseRoot
    if ($keys) {
        foreach ($key in $keys.split(".")) {
            $response = $response.$key
        }
    }

    return $response #| Select-Object -Property $global:OktaRestApiConfig.View.$( $global:OktaRestApiConfig.Method.$Method.View)

}
