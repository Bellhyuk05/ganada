param(
    [Parameter(Mandatory = $true)][string]$AndroidConfig,
    [string]$DevelopmentConfig = 'config/development.json',
    [string]$AndroidPackage = 'com.example.unilink'
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskDestination = [System.IO.Path]::GetFullPath((Join-Path $taskRoot $DevelopmentConfig))
if (-not $taskDestination.StartsWith($taskRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'The destination must stay inside this workspace.'
}
$taskAndroid = Get-Content -LiteralPath $AndroidConfig -Raw | ConvertFrom-Json -AsHashtable
if ($taskAndroid.ContainsKey('private_key') -or $taskAndroid.type -eq 'service_account') {
    throw 'Server credentials are not Android app configuration.'
}
if (-not $taskAndroid.project_info.project_id) {
    throw 'The Firebase project ID is required.'
}
$taskClients = @($taskAndroid.client | Where-Object { $_.client_info.android_client_info.package_name -eq $AndroidPackage })
if ($taskClients.Count -ne 1) { throw 'Exactly one matching Android app is required.' }
$taskApp = $taskClients[0]
$taskKeys = @($taskApp.api_key | Where-Object { $_.current_key })
if ($taskKeys.Count -ne 1) { throw 'Exactly one Android client API key is required.' }
$taskNumber = [string]$taskAndroid.project_info.project_number
$taskAppId = [string]$taskApp.client_info.mobilesdk_app_id
if (-not $taskNumber -or -not $taskAppId.StartsWith("1:${taskNumber}:android:")) {
    throw 'The Firebase app ID must match its project number.'
}
$taskDevelopment = Get-Content -LiteralPath $taskDestination -Raw | ConvertFrom-Json -AsHashtable
$taskDevelopment.FIREBASE_API_KEY = [string]$taskKeys[0].current_key
$taskDevelopment.FIREBASE_APP_ID = $taskAppId
$taskDevelopment.FIREBASE_SENDER_ID = $taskNumber
$taskDevelopment.FIREBASE_PROJECT_ID = [string]$taskAndroid.project_info.project_id
Set-Content -LiteralPath $taskDestination -Value ($taskDevelopment | ConvertTo-Json -Depth 8) -Encoding utf8
Write-Output 'Imported Android public configuration. No server credentials were stored.'
