[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]
Param()

#region PREFLIGHT

    #region CVE-2021-44228
    # mitigate remote code execution vulnerability (CVE-2021-44228) related to Apache Log4j
    # https://msrc-blog.microsoft.com/2021/12/11/microsofts-response-to-cve-2021-44228-apache-log4j2/
    # https://cve.mitre.org/cgi-bin/cvename.cgi?name=2021-44228

        $psSession = Get-PSSession+ -ComputerName (pt nodes -k)
        $result = Invoke-Command -Session $psSession { [Environment]::SetEnvironmentVariable("LOG4J_FORMAT_MSG_NO_LOOKUPS","true","Machine") } 

    #endregion CVE-2021-44228

#endregion PREFLIGHT