# OVERWATCH
Overwatch is a PowerShell application which automates the monitoring and management of software platforms and systems. 

Overwatch currently supports [Tableau Server][], [Tableau Resource Monitoring Tool][] and [Alteryx Server][]. Core functionality includes monitoring of software platforms and their host systems, alerting via multiple messaging providers, backup management, storage management, Azure AD and Azure AD B2C support and Azure Update Management integration. Overwatch also includes numerous additional PowerShell cmdlets for querying and management of the environment.

|  | Supported/Available
|-|-
| OS | Windows Server
| Platforms | [Tableau Server][], [Tableau Resource Monitoring Tool][], [Alteryx Server][]
| Products | Monitor, Backup, Cleanup, DiskCheck, AzureADCache, AzureADSyncTS, AzureADSyncB2C, StartRMTAgents
| Providers | MicrosoftTeams, TwilioSMS, SMTP

_Overwatch is designed for extensibility.  Operating systems and software platforms can be added to the Overwatch service layer, and new functionality can be added by creating new products and providers._

## Contributions

Overwatch was developed by [David Walker][] with support from [PATH][], a global nonprofit working to improve public health and accelerate health equity so all people and communities can thrive.  At PATH, Overwatch monitors and manages PATH's Health Insight Platform, hosted in an Microsoft Azure AD B2C tenant, which provides PATH and other nonprofit organizations with analytic platforms, including Tableau Server and Alteryx Server, as well as access to Azure services and infrastructure.

## License

This project is licensed under the terms of the [GNU GPLv3][] license.

## Requirements

- [PowerShell 7.x][]
- Admin accounts for local machines or AD domains
- Platform-specific admin accounts

## Recommendations

- [Visual Studio Code][]

## Installer

- Automated installation and configuration of the Overwatch environment.
- Persists installation and configuration settings for quick reinstallations/updates.
- Additional products and providers can be installed at any time.
- Capable of updating the installation with the latest versions of code.
- See the [Installation Guide][] for more details.

## Uninstaller

- Automated uninstallation of the Overwatch environment.
- Persists installation/configuration settings and all data for archival or quick reinstallations/updates.
- Individual products and providers can be uninstalled at any time.
- See the [Installation Guide][] for more details.
    
[Overwatch on Github]: https://github.com/dwalker3rd/Overwatch
[Microsoft Teams webhook]: https://docs.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook
[PowerShell 7.x]: https://github.com/PowerShell/PowerShell
[Visual Studio Code]: https://code.visualstudio.com/
[Tableau Server]: https://www.tableau.com/
[Tableau Resource Monitoring Tool]: https://help.tableau.com/current/server/en-us/rmt-intro.htm
[Alteryx Server]: https://www.alteryx.com/
[Microsoft Teams]: https://www.microsoft.com/en-us/microsoft-365/microsoft-teams/group-chat-software
[Twilio SMS]: https://www.twilio.com/sms
[Windows Server]: https://www.microsoft.com/en-us/windows-server
[PATH]: https://path.org
[David Walker]: https://www.linkedin.com/in/dwalker3rd/
[GNU GPLv3]: https://github.com/dwalker3rd/Overwatch/blob/main/LICENSE
[Installation Guide]: https://github.com/dwalker3rd/Overwatch/blob/main/docs/install.md
