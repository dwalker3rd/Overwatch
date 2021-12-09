# OVERWATCH

Overwatch is a PowerShell application which automates the monitoring and management of software platforms and systems.  Currently, Overwatch supports [Tableau Server][] and [Alteryx Server][] running on [Windows Server][].  Core functionality includes the Monitor, Backup, Cleanup, and DiskCheck products with providers for [Microsoft Teams][], [Twilio SMS][] and SMTP.

## Requirements

- [Windows Server][]
- [Powershell 7][] and [Visual Studio Code][]
- Local/Domain account (with admin rights)
- Overwatch service account (with admin rights)

## Download

* Download/Clone Overwatch from [Overwatch on Github][] to the installation (aka root) directory.
    * For [Tableau Server][], the installation directory *must* be on the initial node
    * For [Alteryx Server][], the installation directory *must* be on the controller

## Configuration

Configuration of Overwatch is managed with definition files (PowerShell scripts).  Definition files describe the base environment, operating system, platform, platform instances, products and providers.  Use the tables in the configuration sections below to adapt Overwatch to your environment.

### Environment
The base environment

| Variable | Possible Values  | Notes | Directory | File |
|-|-|-|-|-|
| OS | WindowsServer | | \ | environ.ps1 |
| Platform | TableauServer _or_ AlteryxServer | | \ | environ.ps1 |
| Product | Monitor, Backup, Cleanup, DiskCheck, Command | Command is required | \ | environ.ps1 |
| Provider | MicrosoftTeams, TwilioSMS, SMTP, Views | Views is required | \ | environ.ps1 |
| Location.Root | Full path name | | \ | environ.ps1 |
| Location.Images | URL | Required for Microsoft Teams provider | \ | environ.ps1 |
| Location.Data | Full path name | Must be a local path that exists on all nodes | \ | environ.ps1 |
| Location.Logs | Full path name | Must be a local path that exists on all nodes | \ | environ.ps1 |
| Location.Temp | Full path name | Must be a local path that exists on all nodes | \ | environ.ps1 |

### Platform Instance
An instance of a platform.

| Variable | Possible Values  | Notes | Directory | File |
|-|-|-|-|-|
| Instance | Unique Id | [a-zA-Z-] | \definitions | definitions-platforminstance-\*.ps1 |
| URI | Platform URL | | \definitions | definitions-platforminstance-\*.ps1 |
| PlatformContextType | Application, Domain, Machine | [more info][ContextType] | \definitions | definitions-platforminstance-\*.ps1 |
| PlatformContextName | AD domain, AD LDS instance, ComputerName |  | \definitions | definitions-platforminstance-*.ps1 |

### Product
Products provide functionality.

| Product | Variable | Possible Values  | Notes | Directory | File |
|-|-|-|-|-|-|
| Monitor, Backup, Cleanup, DiskCheck | -At parameter of Register-PlatformTask  | DateTime | | \install | install-product-\*.ps1 |
| Monitor, Backup, Cleanup, DiskCheck | -RepetitionInterval parameter of Register-PlatformTask  | TimeSpan | | \install | install-product-\*.ps1 |

### Provider
Providers are integration points with other systems.

| Provider | Variable | Possible Values  | Notes | Directory | File |
|-|-|-|-|-|-|
| MicrosoftTeams | Connector | [Microsoft Teams webhook][] | | \definitions | definitions-provider-microsoftteams.ps1 | |
| MicrosoftTeams | MessageType | Information, Warning, Alert, AllClear, Task | | \definitions | definitions-provider-microsoftteams.ps1 | |
| SMTP | Server | | | \definitions | definitions-provider-smtp.ps1 |
| SMTP | Port | | | \definitions | definitions-provider-smtp.ps1 |
| SMTP | UseSSL | Boolean | | \definitions | definitions-provider-smtp.ps1 |
| SMTP | From | Email address | | \definitions | definitions-provider-smtp.ps1 |
| SMTP | To | Email addresses | Comma-separated list | \definitions | definitions-provider-smtp.ps1 |
| SMTP | To | null | Use email addresses in \data\contacts.csv | \definitions | definitions-provider-smtp.ps1 |
| SMTP | MessageType | Information, Warning, Alert, AllClear, Task | | \definitions | definitions-provider-smtp.ps1 |
| TwilioSMS | From | Twilio phone number | Twilio SMS account required | \definitions |  definitions-provider-twiliosms.ps1 |
| TwilioSMS | To | Phone numbers | Comma-separated list | \definitions |  definitions-provider-twiliosms.ps1 |
| TwilioSMS | Throttle | TimeSpan | Period to wait before repeating a SMS | \definitions |  definitions-provider-twiliosms.ps1 |
| TwilioSMS | MessageType | Information, Warning, Alert, AllClear, Task | | \definitions |  definitions-provider-twiliosms.ps1 |
| Views | View |  | Passed to -Property parameter of [Select-Object][] | \definitions | definitions-provider-views.ps1 |

## Installation

1. Open PowerShell with "Run As Administrator"
1. Change directory to the install directory
1. Execute \install.ps1
1. Installation steps:
    | Install | Action | Interaction |
    |-|-|-|
    | Platform | Create directories ||
    | Platform | Create log files ||
    | Platform | Request credentials | Credentials requested for Overwatch service/runas account |
    | Product | Install each product defined in $Environ.Product | Confirmation required for some actions |
    | Provider | Install each provider defined in $Environ.Provider | Credentials requested for some providers |
1. If using the Microsoft Teams provider, publish the image files in \img to a public/anon URL
    

[Overwatch on Github]: https://github.com/PATH-Global-Health/Overwatch
[Select-Object]: https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/select-object?view=powershell-7#parameters
[ContextType]: https://docs.microsoft.com/en-us/dotnet/api/system.directoryservices.accountmanagement.contexttype
[Microsoft Teams webhook]: https://docs.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook
[PowerShell 7]: https://github.com/PowerShell/PowerShell/releases
[Visual Studio Code]: https://code.visualstudio.com/
[Tableau Server]: https://www.tableau.com/
[Alteryx Server]: https://www.alteryx.com/
[Microsoft Teams]: https://www.microsoft.com/en-us/microsoft-365/microsoft-teams/group-chat-software
[Twilio SMS]: https://www.twilio.com/sms
[Windows Server]: https://www.microsoft.com/en-us/windows-server
