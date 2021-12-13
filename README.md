# OVERWATCH
Overwatch is a PowerShell application which automates the monitoring and management of software platforms and systems. Overwatch currently supports [Tableau Server][] and [Alteryx Server][] running on [Windows Server][]. Core functionality includes monitoring of software platforms and their host systems, alerting via multiple messaging providers, backup management, storage management, Azure AD and Azure AD B2C support (including AD synchronization for Azure AD B2C tenants and Azure Update Management integration) as well as numerous PowerShell cmdlets for querying and management of the environment.

Overwatch is based on an object hierarchy as follows: 

| Object | Supported/Available
|-|-
| OS | WindowsServer
| Platform | TableauServer _or_ AlteryxServer
| Products | Monitor, Backup, Cleanup, DiskCheck, AzureADSync
| Providers | MicrosoftTeams, TwilioSMS, SMTP

Overwatch can be extended to support other operating systems and software platforms.  For example, to add support for Linux, use the *-os-windowsserver.ps1 files as a guide to create linux-specific versions.  In a similar fashion, new platforms, products and providers can be added to Overwatch.

## Requirements

- [Windows Server][]
- [Powershell 7][]
- [Visual Studio Code][] (Recommended)
- Local/Domain account (with admin rights)
- Admin account for each platform

## Download

* Download/Clone Overwatch from [Overwatch on Github][] to the installation (aka root) directory.
    * For [Tableau Server][], the installation directory *must* be on the initial node
    * For [Alteryx Server][], the installation directory *must* be on the controller

## Installation

1. Open PowerShell with "Run As Administrator"
1. Change directory to the install directory for Overwatch
1. Execute [install.ps1][]
1. If using the Microsoft Teams provider, publish the image files in [\img][] to a public/anon URL
    
[Overwatch on Github]: https://github.com/dwalker3rd/Overwatch
[Microsoft Teams webhook]: https://docs.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook
[PowerShell 7]: https://github.com/PowerShell/PowerShell
[Visual Studio Code]: https://code.visualstudio.com/
[Tableau Server]: https://www.tableau.com/
[Alteryx Server]: https://www.alteryx.com/
[Microsoft Teams]: https://www.microsoft.com/en-us/microsoft-365/microsoft-teams/group-chat-software
[Twilio SMS]: https://www.twilio.com/sms
[Windows Server]: https://www.microsoft.com/en-us/windows-server
[\img]: https://github.com/dwalker3rd/Overwatch/tree/main/img
[install.ps1]: https://github.com/dwalker3rd/Overwatch/blob/main/install.ps1
