$global:RegexClass = @{
    HexDigit = "[0-9a-fA-f]"
    AtoZ = "[a-zA-Z]"
}

$global:RegexPattern = @{
    Guid = "^$($global:RegexClass.HexDigit){8}(-$($global:RegexClass.HexDigit){4}){3}-$($global:RegexClass.HexDigit){12}$"
    StartsWithGuid = "^[0-9a-fA-f]{8}(-[0-9a-fA-f]{4}){3}-[0-9a-fA-f]{12}\@.*$"
    Mail = @"
(?:[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*|`"(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21\x23-\x5b\x5d-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])*`")@(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?|\[(?:(?:(2(5[0-5]|[0-4][0-9])|1[0-9][0-9]|[1-9]?[0-9]))\.){3}(?:(2(5[0-5]|[0-4][0-9])|1[0-9][0-9]|[1-9]?[0-9])|[a-z0-9-]*[a-z0-9]:(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21-\x5a\x53-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])+)\])
"@
    PhoneNumber = "\+?\d{1,4}?[-.\s]?\(?\d{1,3}?\)?[-.\s]?\d{1,4}[-.\s]?\d{1,4}[-.\s]?\d{1,9}"
    SignedInteger = "^(?<sign>\+|-)?(?<number>\d+)$"
    Software = @{
        Build = "(\d+.\d+.\d+.\d+)"
        Version = "(\d+.\d+.\d+)"
    }
    AzureAD = @{
        UserPrincipalName = "^(([\w.]|#EXT#)+)\@(\w+)(\.(\w+))+$"
        MailFromGuestUserUPN = "^(.*)_(.*)#EXT#\@.*$"
    }
    Windows = @{
        ShutdownEvent = @{
            1074 = "The\sprocess\s(?'process'\S*\s\(.*\))\shas\sinitiated\sthe\s(\S*)\sof\scomputer\s(?'computer'\S*)\son\sbehalf\sof\suser\s(?'user'\S.*)\s.*for the following reason:\s(?'reason'.*)\n\s*Reason\sCode:\s*(?'code'.*)\n\s*Shutdown\sType:\s*(?'type'.*)\n\s*Comment:\s*(?'comment'\S?.*)"
            1076 = "The\sreason\ssupplied\sby\suser\s(?'user'\S*)\sfor\sthe\slast\sunexpected\sshutdown\sof\sthis\scomputer\sis:\s(?'reason'.*)\n\s*Reason\sCode:\s*(?'code'.*)\n\s*Bug\sID:\s*(?'bugID'.*)\s*Bugcheck\sString:\s*(?'bugcheckString'.*)\n\s*Comment:\s*(?'comment'\S?.*)"
        }
        ComputerName = "[^\.\\/\:\*\?""\<\>\|]{1}[^\\/\:\*\?""\<\>\|]{0,14}"
        Unc = "^(?:\\\\(?<computername>[^\\]*))?\\?(?'path'(?'drive'[a-zA-Z](?:\$|\:))?\\?(?'directory'.*[\/\\])?(?'filenamewithoutextension'[\w\-_]*)((?'extension'\.\w+)*)?)$"
    }
    WriteHostPlus = @{
        Parse = "^<(.*?)\s<(.)>(\d*)>\s(.*)$"
        UnParse = "^(<\s+)(.*?)(\s*<.*>\s*)(.*)$"
    }
    Download = @{
        ValidFileNameChars = "[0-9a-zA-Z\-_]"
        InvalidFileNameChars = "[^0-9a-zA-Z\-_]"
    }
    ScheduledTask = @{
        RepetitionPattern = "^P(?>(?<day>\d*)D)?T(?>(?<hour>\d*)H)?(?>(?<minute>\d*)M)?(?>(?<second>\d*)S)?$"
    }
    Whitespace = @{
        Trim = "^\s*|\s*$"
        TrimLeading = "^\s*"
        TrimTrailing = "\s*$"
    }

}
