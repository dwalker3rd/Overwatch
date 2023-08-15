#region PLATFORM DEFINITIONS

    $global:Platform =
        [Platform]@{
            Id = "TableauRMT"
            Name = "Tableau RMT"
            DisplayName = "Tableau Resource Monitoring Tool"
            Image = "$($global:Location.Images)/tableau_rmt.png"
            Description = "Tableau Resource Monitoring Tool"
            Publisher = "Tableau Software, LLC, A Salesforce Company"
        }

    $global:RMTControllerAlias = "Master"
    $global:PlatformTopologyBase = @{
            Nodes = @{}
            Components = @{
                Controller = @{
                    Nodes = @{}
                    Services = @("TableauResourceMonitoringTool","TableauResourceMonitoringToolRabbitMQ","TableauResourceMonitoringToolPostgreSQL")
                }
                Agents = @{
                    Nodes = @{}
                    Services = @("TableauResourceMonitoringToolAgent")
                }
            }
            Alias = @{}
        }

    $global:PlatformStatusOK = @("Running")        

    $global:TableauServerStatusOK = @(
        'Active',
        'ActiveSyncing',
        'Busy',
        'Running',
        'Passive',
        'ReadOnly'
    )    

    $global:PlatformStatusColor = @{
        Degraded = "DarkRed"
        Stopping = "DarkYellow"
        Stopped = "DarkRed"
        Starting = "DarkYellow"
        Restarting = "DarkYellow"
        Running = "DarkGreen"
        Connected = "DarkGreen"
        Connecting = "DarkGreen"
        Disconnected = "DarkRed"
        Disconnecting = "DarkRed"
    }

#endregion PLATFORM DEFINITIONS