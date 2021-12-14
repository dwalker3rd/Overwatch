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

1. Clone Overwatch from [Overwatch on Github][].
1. On the target machine, open PowerShell or Visual Studio Code with "Run As Administrator"
1. Change directory to the location where you downloaded/cloned Overwatch.
    * Tableau Server: Overwatch *must* be installed on the initial node.
    * Alteryx Server: Overwatch *must* be installed on the controller.
1. Execute [install.ps1][]

_Note: Values in brackets are the default.  For most questions, the default values are populated first from seetings saved during the previous installation or, if there are no saved settings, from the installer's default settings file._

### Questions

1. Select Platform
    - Default values are first populated with any Overwatch-supported platforms that are installed, and then according to the previous rule.  If there are multiple Overwatch-support platforms installed, you must select one.
1. Platform Install Location
    - Enter the location where the selected platform is installed.
1. Platform Instance ID
    - Enter a unique id for this platform instance.
    - The id may only consist of letters, numbers and a hyphen (-)
    - Example: For Tableau Server installed at https://tableau.yourcompany.com, the platform instance id might be tableau-yourcompany-com.
1. Image URL
    - Enter a publicly-accessible URL where you will publish Overwatch images.
    - The URL must be publicly-accessible to work with the Microsoft Teams provider.
1. Select Products
    - Select the products to install
    - Products must be installed to be available for use
1. Select Providers
    - Select the providers to install
    - During provider installation 
    - Note: At least one messaging provider must be selected for messaging to send notifications/alerts.

_At this point, the installer will create and deploy definition files, create log files, install required PowerShell modules/packages, and initialize the new Overwatch environment._

7. Contacts
    - Contacts are used by Overwatch's messaging service.
    - If at least one contact is not configured, Overwatch will prompt for a name, email address and phone number.
1. Credentials
    - Overwatch requires an account that is an admin of the host server on which it is installed AND of the platform.
    - The account id within Overwatch is "local-admin-\<platformInstanceId\>"
    - if the admin account is not found in the Overwatch vault, you will be prompted to provide the credentials for that account.
    - AD accounts must use the format "domain\userprincipalname".  The format for local accounts on Windows Server may be either ".\username" or "username" depending on the platform.
1. Install Products
    - Products selected above will now be installed.
    - Platform tasks associated with a product will be disabled and must be enabled post-installation.
1. Install Providers
    - Providers selected above will now be installed.
    - It not previously installed, providers may present configuration questions.
    - Example: The SMTP provider will request the server URL, port, whether SSL is required and the SMTP credentials (account and password).

_Once the installation is complete, Overwatch will reinitialize the environ and run preflight checks and updates._

## Post-Installation

### Microsoft Teams Provider

1. Edit the definition file for the platform instance (`/definitions/definitions-platforminstance-<platformInstanceId>.ps1`). 
1. Locate the `$global:MicrosoftTeamsConfig` object.
1. Add your Microsoft Teams webhooks to `$global:MicrosoftTeamsConfig.Connector`. 
1. Publish the image files in the [\img][] folder to the publicly-accessible URL provided during installation.
1. Note that it may take several hours before Microsoft Teams shows the images in messages sent by Overwatch.

### Platform Tasks

1. Platform tasks associated with a product are disabled during installation and must be enabled manually.
    - On Windows Server, you can use the Task Scheduler app, or ...
    - Use the Overwatch command, `Enable-PlatformTask`
1. Platform tasks are configured to run as the admin account provided during installation.  You may need to change the account under which the task runs or modify other parameters.  
    - On Windows Server, use the Task Scheduler app to modify a task's configuration, or 
    - Use the Overwatch commands `Unregister-PlatformTask` and `Register-PlatformTask`.


## Testing

1. `overwatch.ps1` will initialize the Overwatch environment and run preflight tests and updates.
2. `monitor.ps1` will run the Monitor product, display platform status and send notifications/alerts, if necessary.
3. `Send-PlatformStatusMessage -MessageType $PlatformMessageType.Alert -NoThrottle` will send a platform status message through all installed providers.  If there are any issues with messaging provider configuration, such as invalid credentials for the SMTP account, you will see the error here.
    
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
[PATH]: https://path.org
[David Walker]: https://www.linkedin.com/in/dwalker3rd/
[GNU GPLv3]: https://github.com/dwalker3rd/Overwatch/LICENSE
