# OVERWATCH
Overwatch is a PowerShell application which automates the monitoring and management of software platforms and systems. 

Overwatch currently supports [Tableau Server][] and [Alteryx Server][] running on [Windows Server][]. Core functionality includes monitoring of software platforms and their host systems, alerting via multiple messaging providers, backup management, storage management, Azure AD and Azure AD B2C support (including AD synchronization for Azure AD B2C tenants and Azure Update Management integration) as well as numerous PowerShell cmdlets for querying and management of the environment.

| Object | Supported/Available
|-|-
| OS | WindowsServer
| Platforms | TableauServer, AlteryxServer
| Products | Monitor, Backup, Cleanup, DiskCheck, AzureADSync
| Providers | MicrosoftTeams, TwilioSMS, SMTP

_Overwatch is designed for extensibility.  Operating systems and software platforms can be added to the Overwatch service layer, and new functionality can be added by creating new products and providers._

## Contributions

Overwatch was developed by [David Walker][] with support from [PATH][], a global nonprofit working to improve public health and accelerate health equity so all people and communities can thrive.  At PATH, Overwatch monitors and manages PATH's Health Insight Platform, hosted in an Microsoft Azure AD B2C tenant, which provides PATH and other nonprofit organizations with analytic platforms, including Tableau Server and Alteryx Server, as well as access to Azure services and infrastructure.

## License

This project is licensed under the terms of the [GNU GPLv3][] license.

## Requirements

- [Windows Server][]
- [PowerShell 7][]
- [Visual Studio Code][] (Recommended)
- Local/Domain account (with admin rights)
- Admin account for each platform

## Installation

- [Installation Guide][]
    
[Overwatch on Github]: https://github.com/dwalker3rd/Overwatch
[Microsoft Teams webhook]: https://docs.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook
[PowerShell 7]: https://github.com/PowerShell/PowerShell
[Visual Studio Code]: https://code.visualstudio.com/
[Tableau Server]: https://www.tableau.com/
[Alteryx Server]: https://www.alteryx.com/
[Microsoft Teams]: https://www.microsoft.com/en-us/microsoft-365/microsoft-teams/group-chat-software
[Twilio SMS]: https://www.twilio.com/sms
[Windows Server]: https://www.microsoft.com/en-us/windows-server
[PATH]: https://path.org
[David Walker]: https://www.linkedin.com/in/dwalker3rd/
[GNU GPLv3]: https://github.com/dwalker3rd/Overwatch/blob/main/LICENSE
[Installation Guide]: https://github.com/dwalker3rd/Overwatch/blob/main/docs/install.md
