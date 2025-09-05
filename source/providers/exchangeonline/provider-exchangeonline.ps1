function global:Connect-ExchangeOnline+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}    

    $exchangeOnlineCredentials = Get-Credentials "$Tenant-exchangeonline"
    if (!$exchangeOnlineCredentials) {
        throw "Unable to find the Exchange Online credentials `"$Tenant-exchangeonline`""
    }    

    Connect-ExchangeOnline -Credential $exchangeOnlineCredentials -DisableWAM -ShowBanner:$false
    
}

function global:New-MailEnabledSecurityGroup {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false,Position=1)][string]$Type = "Security"
    )

    return New-DistributionGroup -Name $Name -Type $Type

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