# OVERWATCH
Overwatch is a PowerShell application which automates the monitoring and management of software platforms and systems.

|| Supported
|-|-
| OS | Windows Server
| Platforms | Tableau Server, Tableau Cloud, Tableau Resource Monitoring Tool, Alteryx Server, Azure AD, Azure AD B2C
| Products | Monitor, Backup, Cleanup, DiskCheck, AzureADCache, AzureADSyncTS, AzureADSyncB2C, StartRMTAgents, RemoteCommand, ContentManagement, AssetDeployment
| Providers | MicrosoftTeams, TwilioSMS, SMTP, TableauServerWC, ODBC, Postgres, Views

_Overwatch is designed for extensibility.  Support for additional operating systems and software platforms can be added to the Overwatch service layer, and new functionality can be added by creating new products and providers._

## Architecture

Refer to the [Overwatch Architecture Diagram][] for a visual of Overwatch's architecture.

## Contributions

Overwatch was developed by [David Walker][] with support from [PATH][], a global nonprofit working to improve public health and accelerate health equity so all people and communities can thrive.  At PATH, Overwatch monitors and manages PATH's Health Insight Platform, hosted in an Microsoft Azure AD B2C tenant, which provides PATH and other nonprofit organizations with analytic platforms, including Tableau Server and Alteryx Server, as well as access to Azure services and infrastructure.

## License

This project is licensed under the terms of the [GNU GPLv3][] license.

## Requirements

- [Windows Server][]
- [PowerShell 7.x][]
- Admin account for the OS/environ (Local/machine or domain)
- Admin account for each installed platform

## Recommendations

- [Visual Studio Code][]

## Installer / Uninstaller

- Automated install/uninstall of the Overwatch environment.
- Persists installation data for easy reinstallations/updates.
- Individual products and providers can be installed/uinstalled.
- Installer option allows updating the installation with the latest versions of code.
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
[Overwatch Architecture Diagram]: https://github.com/dwalker3rd/Overwatch/blob/main/source/core/docs/img/overwatch_architecture.png?raw=true
