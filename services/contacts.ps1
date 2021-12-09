function global:Get-Contact {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Email,
        [Parameter(Mandatory=$false)][string]$Phone
    )

    $contacts = @()
    Import-Csv -Path $ContactsDB | ForEach-Object {
        $contacts +=
            [Contact]@{
                Name = $_.Name
                Email = $_.Email 
                Phone = $_.Phone
            }
        }

    if ($Name) {$contacts = $contacts | Where-Object {$_.Name -eq $Name}}
    if ($Email) {$contacts = $contacts | Where-Object {$_.Email -eq $Email}}
    if ($Phone) {$contacts = $contacts | Where-Object {$_.Phone -eq $Phone}}

    return $contacts
    
}

function global:Add-Contact {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Email,
        [Parameter(Mandatory=$false)][string]$Phone
    )

    if ($Email -and !$(IsValidEmail $Email)) {throw "Invalid Email"}
    if ($Phone -and !$(IsValidPhone $Phone)) {throw "Invalid Phone"}

    $contacts = Get-Contact
    if ($($contacts | Where-Object {$_.Name -eq $Name})) {
        throw "Contact $($Name) already exists."
        return
    }
    if ($Email -and $($contacts | Where-Object {$_.Email -eq $Email})) {
        throw "Email $($Email) already in use."
        return
    }
    if ($Phone -and $($contacts | Where-Object {$_.Phone -eq $Phone})) {
        throw "Phone $($Phone) already in use."
        return
    }

    [Contact]@{
        Name = $Name
        Email = $Email
        Phone = $Phone
    } | Export-Csv -Path $ContactsDB -Append -UseQuotes Always -NoTypeInformation
    
}

function global:Update-Contact {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Email,
        [Parameter(Mandatory=$false)][string]$Phone,
        [switch]$Remove
    )

    if ($Email -and !$(IsValidEmail $Email)) {throw "Invalid Email"}
    if ($Phone -and !$(IsValidPhone $Phone)) {throw "Invalid Phone"}

    $contacts = Get-Contact
    if (!$($contacts | Where-Object {$_.Name -eq $Name})) {
        throw "Contact $($Name) not found."
        return
    }
    if ($Email -and $($contacts | Where-Object {$_.Email -eq $Email})) {
        throw "Email $($Email) already in use."
        return
    }
    if ($Phone -and $($contacts | Where-Object {$_.Phone -eq $Phone})) {
        throw "Phone $($Phone) already in use."
        return
    }

    $contact = $contacts | Where-Object {$_.Name -eq $Name}

    $contact.Email = $Email ? $Email : $_.Email
    $contact.Phone = $Phone ? $Phone : $_.Phone

    $contacts = Get-Contact | Where-Object {$_.Name -ne $Name} 
    if (!$Remove) {$contacts = [array]$contacts + [array]$contact}
    
    $contacts | Export-Csv -Path $ContactsDB -UseQuotes Always -NoTypeInformation

}

function global:Remove-Contact {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name
    )

    Update-Contact -Name $Name -Remove
}

function global:IsValidEmail { 
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Email
    )

    try {
        $null = [mailaddress]$Email
        return $true
    }
    catch {
        return $false
    }
}


function global:IsValidPhone { 
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Phone
    )

    try {
        $null = $Phone -match $global:RegexPattern.PhoneNumber
        return $true
    }
    catch {
        return $false
    }
}