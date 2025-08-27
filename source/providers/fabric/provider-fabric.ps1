function global:Connect-Fabric {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}    

    $tokenType = "Bearer"
    $accessToken += (Get-AzAccessToken -ResourceUrl "https://api.fabric.microsoft.com").Token | ConvertFrom-SecureString -AsPlainText
    $global:Azure.$tenantKey.Fabric.RestAPI.AccessToken = "$tokenType $accessToken"
    $global:Azure.$tenantKey.Fabric.RestAPI.Headers = @{ Authorization = $global:Azure.$tenantKey.Fabric.RestAPI.AccessToken; "Content-Type" = "application/json" }

}

function global:Get-Capacities {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}       

    $response = Invoke-RestMethod -Method GET `
        -Uri "$($global:Azure.$tenantKey.Fabric.RestAPI.BaseUri)/capacities" `
        -Headers $global:Azure.$tenantKey.Fabric.RestAPI.Headers 
    $capacities = $response.value
    return $capacities 

}

function global:Get-Capacity {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][string]$Name
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) { throw "$tenantKey is not a valid/configured AzureAD tenant." }       

    $capacities = Get-Capacities -Tenant $Tenant
    $capacity = $capacities | Where-Object { $_.displayName -eq $Name }
    return $capacity

}

function global:Get-Workspaces {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}  

    $response = Invoke-RestMethod -Method GET `
        -Uri "$($global:Azure.$tenantKey.Fabric.RestAPI.BaseUri)/workspaces" `
        -Headers $global:Azure.$tenantKey.Fabric.RestAPI.Headers 
    $workspaces = $response.value

    return $workspaces

}

function global:Get-Workspace {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0,ParameterSetName="ByName")]
        [Parameter(Mandatory=$true,Position=0,ParameterSetName="ById")][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1,ParameterSetName="ByName")][string]$Name,
        [Parameter(Mandatory=$true,Position=1,ParameterSetName="ById")][string]$Id
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}  

    $workspaceId = $Id
    if ($Name) {
        $_workspaces = Get-Workspaces -Tenant $Tenant
        $_workspace = $_workspaces | Where-Object { $_.displayName -eq $Name }
        $workspaceId = $_workspace.Id
    }

    $workspace = Invoke-RestMethod -Method GET `
        -Uri "$($global:Azure.$tenantKey.Fabric.RestAPI.BaseUri)/workspaces/$workspaceId" `
        -Headers $global:Azure.$tenantKey.Fabric.RestAPI.Headers     

    return $workspace

}

function global:New-Workspace {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][string]$Name
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}       

    $body = @{ displayName = $Name } | ConvertTo-Json
    $workspace = Invoke-RestMethod -Method POST `
        -Uri "$($global:Azure.$tenantKey.Fabric.RestAPI.BaseUri)/workspaces" `
        -Headers $global:Azure.$tenantKey.Fabric.RestAPI.Headers `
        -Body $body
    return $workspace

}

function global:Update-Workspace {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][object]$Workspace,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Description
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) { throw "$tenantKey is not a valid/configured AzureAD tenant." }  

    # if (!$Name -and !$Description) {
    #     throw "At least one of the following is required: -Name or -Description "
    # }

    $_body = @{}
    if ($Name) { $_body += @{ displayName = $Name } }
    if ($Description) { $_body += @{ description = $Description } }
    $body = $_body | ConvertTo-Json
    $workspace = Invoke-RestMethod -Method PATCH `
        -Uri "$($global:Azure.$tenantKey.Fabric.RestAPI.BaseUri)/workspaces/$($Workspace.Id)" `
        -Headers $global:Azure.$tenantKey.Fabric.RestAPI.Headers `
        -Body $body

    return $Workspace

}

function global:Set-WorkspaceCapacity {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][object]$Workspace,
        [Parameter(Mandatory=$true,Position=2)][object]$Capacity
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) { throw "$tenantKey is not a valid/configured AzureAD tenant." }         

    $body = @{ capacityId = $Capacity.Id } | ConvertTo-Json
    $response = Invoke-RestMethod -Method POST `
        -Uri "$($global:Azure.$tenantKey.Fabric.RestAPI.BaseUri)/workspaces/$($Workspace.Id)/assignToCapacity" `
        -Headers $global:Azure.$tenantKey.Fabric.RestAPI.Headers `
        -Body $body
    $response | Out-Null

    return Get-Workspace -Tenant $tenantKey -Id $Workspace.Id

}

function global:Remove-WorkspaceCapacity {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][object]$Workspace
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) { throw "$tenantKey is not a valid/configured AzureAD tenant." }      

    $response = Invoke-RestMethod -Method POST `
        -Uri "$($global:Azure.$tenantKey.Fabric.RestAPI.BaseUri)/workspaces/$($Workspace.Id)/unassignFromCapacity" `
        -Headers $global:Azure.$tenantKey.Fabric.RestAPI.Headers
    $response | Out-Null

    return Get-Workspace -Tenant $tenantKey -Id $Workspace.Id

}

function global:Remove-Workspace {

    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High'        
    )]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][object]$Workspace
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) { throw "$tenantKey is not a valid/configured AzureAD tenant." }  

    $response = $null
    if ($PSCmdlet.ShouldProcess($Workspace.displayName, "Delete workspace")) {
        $response = Invoke-RestMethod -Method DELETE `
            -Uri "$($global:Azure.$tenantKey.Fabric.RestAPI.BaseUri)/workspaces/$($Workspace.Id)" `
            -Headers $global:Azure.$tenantKey.Fabric.RestAPI.Headers
    }

    return $response

}

function global:Get-WorkspaceRoleAssignments {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][object]$Workspace
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) { throw "$tenantKey is not a valid/configured AzureAD tenant." }  

    $response = Invoke-RestMethod -Method GET `
        -Uri "$($global:Azure.$tenantKey.Fabric.RestAPI.BaseUri)/workspaces/$($Workspace.Id)/roleAssignments" `
        -Headers $global:Azure.$tenantKey.Fabric.RestAPI.Headers
    $workspaceRoleAssignments = $response.value
    
    return $workspaceRoleAssignments

}

function global:Get-WorkspaceRoleAssignment {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0,ParameterSetName="ByUPN")]
        [Parameter(Mandatory=$true,Position=0,ParameterSetName="ById")][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1,ParameterSetName="ByUPN")][object]$Workspace,
        [Parameter(Mandatory=$true,Position=2,ParameterSetName="ByUPN")][Alias("UPN")][string]$UserPrincipalName,
        [Parameter(Mandatory=$true,Position=1,ParameterSetName="ById")][string]$Id
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}  

    $workspaceRoleAssignmentId = $Id
    if ($UserPrincipalName) {
        $_workspaceRoleAssignments = Get-WorkspaceRoleAssignments -Tenant $Tenant -Workspace $Workspace
        $_workspaceRoleAssignment = $_workspaceRoleAssignments | Where-Object { $_.principal.userDetails.userPrincipalName -eq $UserPrincipalName }
        $workspaceRoleAssignmentId = $_workspaceRoleAssignment.Id
    }

    $workspaceRoleAssignment = Invoke-RestMethod -Method GET `
        -Uri "$($global:Azure.$tenantKey.Fabric.RestAPI.BaseUri)/workspaces/$($Workspace.Id)/roleAssignments/$workspaceRoleAssignmentId" `
        -Headers $global:Azure.$tenantKey.Fabric.RestAPI.Headers

    return $workspaceRoleAssignment

}

function global:Set-WorkspaceRoleAssignment {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][object]$Workspace,
        [Parameter(Mandatory=$true,Position=2)][Alias("UPN")][string]$UserPrincipalName,
        [Parameter(Mandatory=$true,Position=3)][ValidateSet("Admin","Contributor","Member","Viewer")][string]$Role
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) { throw "$tenantKey is not a valid/configured AzureAD tenant." } 

    $azureADUser = Get-AzureADUser -Tenant $Tenant -User $UserPrincipalName

    $body = @{ principal = @{ type = "User"; id = $azureADUser.id}; role = $Role } | ConvertTo-Json
    $workspaceRoleAssignment = Invoke-RestMethod -Method POST `
        -Uri "$($global:Azure.$tenantKey.Fabric.RestAPI.BaseUri)/workspaces/$($Workspace.Id)/roleAssignments" `
        -Headers $global:Azure.$tenantKey.Fabric.RestAPI.Headers `
        -Body $body
    
    return $workspaceRoleAssignment

}

function global:Update-WorkspaceRoleAssignment {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][object]$Workspace,
        [Parameter(Mandatory=$true,Position=2)][object]$WorkspaceRoleAssignment,
        [Parameter(Mandatory=$true,Position=3)][ValidateSet("Admin","Contributor","Member","Viewer")][string]$Role
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) { throw "$tenantKey is not a valid/configured AzureAD tenant." } 

    $body = @{ role = $Role } | ConvertTo-Json
    $workspaceRoleAssignment = Invoke-RestMethod -Method PATCH `
        -Uri "$($global:Azure.$tenantKey.Fabric.RestAPI.BaseUri)/workspaces/$($Workspace.Id)/roleAssignments/$($WorkspaceRoleAssignment.id)" `
        -Headers $global:Azure.$tenantKey.Fabric.RestAPI.Headers `
        -Body $body
    
    return $workspaceRoleAssignment

}

function global:Remove-WorkspaceRoleAssignment {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][object]$Workspace,
        [Parameter(Mandatory=$true,Position=2)][object]$WorkspaceRoleAssignment
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) { throw "$tenantKey is not a valid/configured AzureAD tenant." } 


    $response = Invoke-RestMethod -Method DELETE `
        -Uri "$($global:Azure.$tenantKey.Fabric.RestAPI.BaseUri)/workspaces/$($Workspace.Id)/roleAssignments/$($WorkspaceRoleAssignment.Id)" `
        -Headers $global:Azure.$tenantKey.Fabric.RestAPI.Headers

    return $response

}