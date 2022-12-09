
$global:Product = @{Id="AzureProjects"}

<# 
    AzureProjects.ps1 has no code, no task, no functionality of its own - at least,
    not for now (future plans include an Overwatch UI). All the functionality that 
    manages Azure projects is actually located in the Azure services layer.  The 
    reason for having an "empty" product is that it allows for configuration by the
    Overwatch installer that would be difficult for a non-core service layer.  For
    example, the installation of the AzureProjects product creates the necessary 
    directory structure for Azure projects and manages the deployment and project
    configuration data.
#>