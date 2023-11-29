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
    HostName = @{
        DNS = "[A-Za-z0-9-\.]{2,63}"
        NetBios = "[^\\/:\*\?`"\<\>\|]{0,14}"
        Windows = "" # aliased below
    }
    DomainName = @{
        DNS = "[A-Za-z0-9-\.]{2,255}"
        NetBios = "[^,~\:!@\$%\^&'\.\(\)\{\}_\s\\/{0,14}]"
    }
    UserName = @{
        NetBios = "^(?:\.\\|(?'ComputerName'[\w_-]*)\\)?(?'Username'\w*)$"
        ActiveDirectory = "^(?'Username'\w+)\@(?'Domain'(\w+)(\.(\w+))+)$"
        AzureAD = "^(?'Username'([\w.]|#EXT#)+)\@('Domain'(\w+)(\.(\w+))+)$"
        AD = "" # aliased below
        DownLevelLogonName = "" # aliased below
    }
    Windows = @{
        ShutdownEvent = @{
            1074 = "The\sprocess\s(?'process'\S*\s\(.*\))\shas\sinitiated\sthe\s(\S*)\sof\scomputer\s(?'computer'\S*)\son\sbehalf\sof\suser\s(?'user'\S.*)\s.*for the following reason:\s(?'reason'.*)\n\s*Reason\sCode:\s*(?'code'.*)\n\s*Shutdown\sType:\s*(?'type'.*)\n\s*Comment:\s*(?'comment'\S?.*)"
            1076 = "The\sreason\ssupplied\sby\suser\s(?'user'\S*)\sfor\sthe\slast\sunexpected\sshutdown\sof\sthis\scomputer\sis:\s(?'reason'.*)\n\s*Reason\sCode:\s*(?'code'.*)\n\s*Bug\sID:\s*(?'bugID'.*)\s*Bugcheck\sString:\s*(?'bugcheckString'.*)\n\s*Comment:\s*(?'comment'\S?.*)"
        }
        ComputerName = "[^\.\\/\:\*\?""\<\>\|]{1}[^\\/\:\*\?""\<\>\|]{0,14}"
        Unc = "^(?:\\\\(?<computername>[^\\]*))?\\?(?'path'(?'drive'[a-zA-Z](?:\$|\:))?\\?(?'directory'.*[\/\\])?(?'filenamewithoutextension'[\w\-_\.]*?)((?'extension'\.\w+)*)?)$"
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
    NuGet = @{
        Version = @{
            Notation = "^(?'versionMajor'\d+)\.?(?'versionMinor'\d+)?\.?(?'versionPatch'\d+)?$"
            Range = @{
                Notation = "^(?'bracketLeft'\[?\(?)(?'versionRangeMinimum'(\d+(\.\d+)*)?)(?'comma'\,?)(?'versionRangeMaximum'(\d+(\.\d+)*)?)(?'bracketRight'\]?\)?)$"
            }
        }
    }
    Overwatch = @{
        Registry = @{
            Path = "\s*Installation\s*=\s*\@\{\s*Registry\s*=\s*\@\{\s*Path\s*=\s*`"(?'OverwatchRegistryPath'.*?)`""
        }
    }
}

# Aliases
$global:RegexPattern.Username.DownLevelLogonName = $global:RegexPattern.Username.NetBios
$global:RegexPattern.Username.AD = $global:RegexPattern.Username.ActiveDirectory
$global:RegexPattern.Username.Windows = $global:RegexPattern.Username.NetBios