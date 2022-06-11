function global:Publish-TSContentChunked {

    [CmdletBinding()]
    param (
        # [Parameter(Mandatory=$true][Alias("Workbook","Datasource","Flow")][object]$InputObject,
        [Parameter(Mandatory=$true,Position=0)][string]$Path,
        [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectId,
        [Parameter(Mandatory=$false)][string]$Name = (Split-Path $Path -LeafBase),
        [Parameter(Mandatory=$false)][ValidateSet("twb","twbx","tde","tds","tdsx","hyper","tfl","tflx")][string]$Extension = ((Split-Path $Path -Extension).TrimStart(".")),
        [Parameter(Mandatory=$false)][switch]$Progress = $global:ProgressPreference -eq "Continue"
    )

    #region VALIDATION

        # If ($InputObject) {
        #     if (!$Path -and !$InputObject.outFile) {
        #         Write-Host+ -NoTrace "The path of the file to upload must be specified in the `'outFile`' property of the `'InputObject`' or the `'Path`' parameter"  -ForegroundColor Red
        #         return
        #     }
        #     elseif (!$Path) { $Path = $InputObject.outFile}
        #     if (!$ProjectId) { $ProjectId = $InputObject.project.id}
        # }

    #endregion VALIDATION
    #region DEFINITIONS

        $uriBase = "https://$($global:tsRestApiConfig.Server)/api/$($global:tsRestApiConfig.RestApiVersioning.ApiVersion)/sites/$($global:tsRestApiConfig.SiteId)"
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("X-Tableau-Auth", $global:tsRestApiConfig.Token)

        $fileName = $Name + "." + $Extension 
        $objectName = [string]::IsNullOrEmpty($Name) ? $Name : $Name
        
        $workbookExtensions = @("twb","twbx")
        $datasourceExtensions = @("tde","tds","tdsx","hyper")
        $flowExtensions = @("tfl","tflx")

        $Type = ""
        if ($Extension -in $workbookExtensions) { $Type = "workbook" }
        if ($Extension -in $datasourceExtensions) { $Type = "datasource" }
        if ($Extension -in $flowExtensions) { $Type = "flow" }

        $fileSize = (Get-ChildItem $Path).Length

    #endregion DEFINITIONS
    #region INITIATE FILE UPLOAD        

        $uploadSessionId = Invoke-TSMethod -Method InitiateFileUpload 

    #endregion INITIATE FILE UPLOAD
    #region APPEND TO FILE UPLOAD

        [console]::CursorVisible = $false

        $message =  "Uploading $Type `'$fileName`' : PENDING$($emptyString.PadLeft(9," "))"
        Write-Host+ -Iff $Progress -NoTrace -NoNewLine -NoSeparator $message.Split(":")[0],(Write-Dots -Length 58 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

        $chunkSize = 1mb
        $progressSizeInt = 1mb
        $progressSizeString = "mb"
        if ($fileSize/$progressSizeInt -le 1) {
            $progressSizeInt = 1kb
            $progressSizeString = "kb"
        }

        $chunk = New-Object byte[] $chunkSize
        $fileStream = [System.IO.File]::OpenRead($Path)

        $bytesReadTotal = 0
        $chunkCount = 1
        while ($bytesRead = $fileStream.Read($chunk, 0, $chunkSize)) {

            # track bytes read
            $bytesReadTotal += $bytesRead
            
            # multipart/form-data, string content
            $multipartContent = [System.Net.Http.MultipartFormDataContent]::new()
            $stringHeader = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new("form-data")
            $stringHeader.Name = "`"request_payload`""
            $stringContent = [System.Net.Http.StringContent]::new("")
            $stringContent.Headers.ContentDisposition = $stringHeader
            $stringContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("text/xml")
            $multipartContent.Add($stringContent)

            # multipart/form-data, byte array content
            $byteArrayHeader = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new("form-data")
            $byteArrayHeader.Name = "`"tableau_file`""
            $byteArrayHeader.FileName = "`"$objectName`""
            # adjust length of last chunk!
            $byteArrayContent = [System.Net.Http.ByteArrayContent]::new($chunk[0..($bytesRead-1)])
            $byteArrayContent.Headers.ContentDisposition = $byteArrayHeader
            $byteArrayContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")
            $multipartContent.Add($byteArrayContent)

            $body = $multipartContent

            # Content-Type header mod
            # tableau requires that the multipart/form-data payload be defined as multipart/mixed
            $contentType = ($body.headers | where-object {$_.key -eq "Content-Type"}).value -replace "form-data","mixed"
            $body.Headers.Remove("Content-Type") | Out-Null
            $body.Headers.Add("Content-Type",$contentType)

            $responseError = $null
            try {
                $response = Invoke-RestMethod "$uriBase/fileUploads/$uploadSessionId" -Method 'PUT' -Headers $headers -Body $body
                $responseError = $response.tsResponse.error
            }
            catch {
                $responseError = $_.Exception.Message
            }
            finally {
                $fileSizeString = "$([math]::Round($fileSize/$progressSizeInt,0))"
                $fileSizeString = "$($fileSizeString.PadLeft($fileSizeString.Length))$progressSizeString"
                $bytesReadTotalString = "$([math]::Round($bytesReadTotal/$progressSizeInt,0))"
                $bytesReadTotalString = "$($bytesReadTotalString.PadLeft($fileSizeString.Length))$progressSizeString"
            }

            if ($responseError) {

                $errorMessage = "Error at AppendToFileUpload (Chunk# $chunkCount): "
                if ($responseError.code) {
                    $errorMessage += "$($responseError.code)$((IsRestApiVersioning -Method $Method) ? " $($responseError.summary)" : $null): $($responseError.detail)"
                }
                else {
                    $errorMessage += $responseError
                }

                $message = "$($emptyString.PadLeft(16,"`b"))FAILURE$($emptyString.PadLeft(16-$bytesUploaded.Length," "))"
                Write-Host+ -Iff $Progress -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor Red
                [console]::CursorVisible = $true

                $fileStream.Close()

                throw $errorMessage
                
            }

            $message = "$($emptyString.PadLeft(16,"`b"))$bytesReadTotalString","/","$fileSizeString$($emptyString.PadLeft(16-($bytesReadTotalString.Length + 1 + $fileSizeString.Length)," "))"
            Write-Host+ -Iff $Progress -NoTrace -NoNewLine -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen,DarkGray,DarkGray

            $chunkCount++

        }

        $message = "$($emptyString.PadLeft(16,"`b"))$bytesReadTotalString","/","$fileSizeString$($emptyString.PadLeft(16-($bytesReadTotalString.Length + 1 + $fileSizeString.Length)," "))"
        Write-Host+ -Iff $Progress -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen,DarkGray,DarkGreen

        [console]::CursorVisible = $true

    #endregion APPEND TO FILE UPLOAD        
    #region FINALIZE UPLOAD

        # multipart/form-data, string content
        $multipartContent = [System.Net.Http.MultipartFormDataContent]::new()
        $stringHeader = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new("form-data")
        $stringHeader.Name = "`"request_payload`""
        $stringContent = [System.Net.Http.StringContent]::new("<tsRequest><$Type name=`"$objectName`"><project id=`"$ProjectId`"/></$Type></tsRequest>")
        $stringContent.Headers.ContentDisposition = $stringHeader
        $stringContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("text/xml")
        $multipartContent.Add($stringContent)

        $body = $multipartContent

        # Content-Type header mod
        # tableau requires that the multipart/form-data payload be defined as multipart/mixed
        $contentType = ($body.headers | where-object {$_.key -eq "Content-Type"}).value -replace "form-data","mixed"
        $body.Headers.Remove("Content-Type") | Out-Null
        $body.Headers.Add("Content-Type",$contentType)

        $responseError = $null
        try {
            $response = Invoke-RestMethod "$uriBase/$($Type)s?uploadSessionId=$uploadSessionId&$($Type)Type=$Extension&overwrite=true" -Method 'POST' -Headers $headers -Body $body
            $responseError = $response.tsResponse.error
        }
        catch {
            $responseError = $_.Exception.Message
        }
        finally {        
            $fileStream.Close()
        }

        if ($responseError) {
            $errorMessage = "Error at Publish$((Get-Culture).TextInfo.ToTitleCase($Type)): "
            if ($responseError.code) {
                $errorMessage = "$($responseError.code)$((IsRestApiVersioning -Method $Method) ? " $($responseError.summary)" : $null): $($responseError.detail)"
            }
            else {
                $errorMessage = $responseError
            }
            throw $errorMessage
        }

        return $response.tsResponse.$Type

    #endregion FINALIZE UPLOAD        

}