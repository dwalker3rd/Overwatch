function global:Connect-ExchangeOnline+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}    

    $exchangeOnlineCredentials = Get-Credentials "$tenantKey-exchangeonline"
    if (!$exchangeOnlineCredentials) {
        throw "Unable to find the Exchange Online credentials `"$tenantKey-exchangeonline`""
    }    

    Connect-ExchangeOnline -Credential $exchangeOnlineCredentials -DisableWAM -ShowBanner:$false
    
}

function global:Get-MailEnabledSecurityGroup {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Identity
    )

    return Get-DistributionGroup -Identity $Identity

}

function global:New-MailEnabledSecurityGroup {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false,Position=1)][string]$Type = "Security"
    )

    return New-DistributionGroup -Name $Name -Type $Type

}

function global:Rename-MailEnabledSecurityGroup {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Identity,
        [Parameter(Mandatory=$false,Position=1)][string]$DisplayName
    )

    return Set-DistributionGroup -Identity $Identity -DisplayName $DisplayName

}

function global:Remove-MailEnabledSecurityGroup {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][Alias("Identity")][string]$Group
    )

    Remove-DistributionGroup -Identity $Group -Confirm:$false

}

function global:Add-MailEnabledSecurityGroupMember {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Group,
        [Parameter(Mandatory=$true,Position=1)][string]$Member
    )

    Add-DistributionGroupMember -Identity $Group -Member $Member

}

function global:Remove-MailEnabledSecurityGroupMember {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Group,
        [Parameter(Mandatory=$true,Position=1)][string]$Member
    )

    Remove-DistributionGroupMember -Identity $Group -Member $Member -Confirm:$false

}