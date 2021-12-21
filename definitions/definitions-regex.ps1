$global:RegexClass = @{
    HexDigit = "[0-9a-fA-f]"
}

$global:RegexPattern = @{
    Guid = "^$($global:RegexClass.HexDigit){8}(-$($global:RegexClass.HexDigit){4}){3}-$($global:RegexClass.HexDigit){12}$"
    Mail = "^(\w+)\@(\w+)(\.(\w+))+$"   
}
$global:RegexPattern += @{
    PhoneNumber = "\+?\d{1,4}?[-.\s]?\(?\d{1,3}?\)?[-.\s]?\d{1,4}[-.\s]?\d{1,4}[-.\s]?\d{1,9}"
    Software = @{
        Build = "(\d+.\d+.\d+.\d+)"
        Version = "(\d+.\d+.\d+)"
    }
    AzureAD = @{
        UserPrincipalName = "^(([\w.]|#EXT#)+)\@(\w+)(\.(\w+))+$"
        MailFromGuestUserUPN = @{
            Match = "^(.*)_(.*)#EXT#\@.*$"
            Substitution = $("$($Matches[1])@$($Matches[2])")
        }
    }
    Windows = @{
        ShutdownEvent = @{
            1074 = "The\sprocess\s(?'process'\S*\s\(.*\))\shas\sinitiated\sthe\s(\S*)\sof\scomputer\s(?'computer'\S*)\son\sbehalf\sof\suser\s(?'user'\S*)\s.*:\s(?'reason'.*)\n\s*Reason\sCode:\s*(?'code'.*)\n\s*Shutdown\sType:\s*(?'type'.*)\n\s*Comment:\s*(?'comment'\S?.*)"
            1076 = "The\sreason\ssupplied\sby\suser\s(?'user'\S*)\sfor\sthe\slast\sunexpected\sshutdown\sof\sthis\scomputer\sis:\s(?'reason'.*)\n\s*Reason\sCode:\s*(?'code'.*)\n\s*Bug\sID:\s*(?'bugID'.*)\s*Bugcheck\sString:\s*(?'bugcheckString'.*)\n\s*Comment:\s*(?'comment'\S?.*)"
        }
    }
}