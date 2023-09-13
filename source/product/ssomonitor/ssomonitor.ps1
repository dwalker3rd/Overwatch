#Requires -RunAsAdministrator
#Requires -Version 7

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"
$global:WriteHostPlusPreference = "Continue"

# product id must be set before definitions
$global:Product = @{Id="SSOMonitor"}
. $PSScriptRoot\definitions.ps1

Write-Host+ -ResetIndentGlobal

$ttlExceptionPattern = "Saml2 Status Code: Requester->  Saml2 Status Message: The request exceeds the allowable time to live."
$ssoRestartPattern = "SAML2 IdP .* successfully configured"
$sleepDuration = 5
$sleepUnits = "Seconds"
$sleepUnitsAbbreviation = $sleepUnits.Substring(0,1).ToLower()

do {

    #region GALLERY CHECK

        $galleryNodes = pt components.gallery.nodes -k -online
        foreach ($node in $galleryNodes) {

            $message = "<SSO status on $node <.>48> PENDING"
            Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

            #region SERVER CHECK

                # Do NOT continue if ...
                #   1. the host server is starting up or shutting down
                #   2. the platform is not running

                # check for server shutdown/startup events
                $serverStatus = Get-ServerStatus -ComputerName $node
                
                # abort if a server startup/reboot/shutdown is in progress
                if ($serverStatus -in ("Startup.InProgress","Shutdown.InProgress")) {
                    $action = "Monitor"; $target = "SSOLogger"; $status = "Aborted"
                    $message = "  Server $($ServerEvent.($($serverStatus.Split("."))[0]).ToUpper()) is $($ServerEventStatus.($($serverStatus.Split("."))[1]).ToUpper())"
                    Write-Log -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
                    Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
                    continue
                }

                # check for platform events from the platformStatus cache
                # usually Get-PlatformStatus is necessary to get real-time status and events
                # however, performance/speed is critical for this product so it must rely on updates by other products
                # warning: this might result in missing events that have occurred in the past few minutes (~five minutes)
                $platformStatus = Read-Cache platformStatus

                # abort if a platform event is in progress
                if (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted) {
                    $action = "Monitor"; $target = "SSOLogger"; $status = "Aborted"
                    $message = $platformStatus.IsStopped ? "  Platform is STOPPED" : "  Platform $($platformStatus.Event.ToUpper()) $($platformStatus.EventStatus.ToUpper())"
                    Write-Log -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
                    Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
                    continue
                }    

            #endregion SERVER CHECK     
            #region ALTERYXSERVICE CHECK

                $alteryxServerStatus = (Get-AlteryxServerStatus -ComputerName $node).Status
                if ($alteryxServerStatus -ne "Running") { 
                    $message = "$($emptyString.PadLeft(8,"`b")) FAILURE"
                    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor Red   
                    $action = "Monitor"; $target = "SSOLogger"; $status = "Aborted"
                    $message = "Gallery on $node is $($alteryxServerStatus.ToUpper())"
                    Write-Log -Target $target -Action $action -Status $status -Message $message -EntryType Error -Force
                    Write-Host+ -NoTrace $message -ForegroundColor Red
                    continue
                }

            #endregion ALTERYXSERVICE CHECK            
            #region SSOLOGGER CHECK

                # get timestamp from last check for this gallery node
                $ssoLogTimestampCache = Read-Cache ssoLogTimestamp
                $ssoLogTimestamp = $ssoLogTimestampCache.$node ?? [datetime]::MinValue

                # read most recent SSO log
                $ssoLogFilePath = ((Get-Files -Path "C:\ProgramData\Alteryx\Logs\alteryx-sso-*.csv" -ComputerName $node).FileInfo | Sort-Object -Property LastWriteTime | Select-Object -Last 1).FullName
                $ssoLogContent = Import-Csv -Path $ssoLogFilePath -Encoding Unicode | Where-Object {$_.Date -gt $ssoLogTimestamp} | Sort-Object -Property Date

                $isOk = $true

                # process log entries since last timestamp
                if ($ssoLogContent) {

                    # search for TTL error; if found restart gallery
                    foreach ($ssoLogEntry in $ssoLogContent) {
                        if ($ssoLogEntry.Exception -match $ttlExceptionPattern) { 

                            $message = "$($emptyString.PadLeft(8,"`b")) ERROR  "
                            Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor Red

                            $message = "The request exceeds the allowable time to live."
                            $target = "Requestor"
                            $action = "SAMLAssertion"
                            $data = $ssoLogEntry | Select-Object -Property Server | ConvertTo-Json -Compress

                            Write-Log -Action $action -Target $target -EntryType Error -Status Error -TimeStamp $ssoLogEntry.Date -Message $message -Data $data
                            Write-Host+ -NoTrace "$message" -ForegroundColor Red

                            # using ptoffline and ptonline instead of restart-gallery
                            # this should prevent the monitor product from sending platform degraded messages
                            # ptOffline $node
                            # ptOnline $node

                            # but using Invoke-AlteryxService is way faster!
                            Invoke-AlteryxService stop -ComputerName $node    
                            Invoke-AlteryxService start -ComputerName $node

                            # re-read SSO log file to get content updates resulting from gallery restart
                            $ssoLogContent = Import-Csv -Path $ssoLogFilePath -Encoding Unicode | 
                                Where-Object {$_.Date -gt $ssoLogContent[-1].Date} | 
                                    Sort-Object -Property Date -Descending | 
                                        Where-Object {$_.Message -match $ssoRestartPattern}

                            $isOk = $false
                            break

                        }
                    }

                    if ($isOk) {
                        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS"
                        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen       
                    }     

                    # update last check timestamp for this node
                    if ($ssoLogTimestampCache.$node) {
                        $ssoLogTimestampCache.$node = $ssoLogContent[-1].Date
                    }
                    else {
                        $ssoLogTimestampCache += @{$node = $ssoLogContent[-1].Date}
                    }
                    $ssoLogTimestampCache | Write-Cache ssoLogTimeStamp

                }
                else {
                    
                    $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS"
                    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

                }

            #endregion SSOLOGGER CHECK            

        }

    #endregion GALLERY CHECK 
    
    $message = "<$($Product.Id) sleep duration ($($sleepUnits.ToLower())) <.>48> $sleepDuration$($sleepUnitsAbbreviation)"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,Gray -Verbose

    # sleep
    Invoke-Expression "Start-Sleep -$sleepUnits $sleepDuration"

} while (
    $true
)