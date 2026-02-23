# =================================
# RipClip Module Entry
# =================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------
# Module-Level State
# ---------------------------------

# Inside a module, $PSScriptRoot already equals:
# ...\src\RipClip
$script:RipClipRoot = $PSScriptRoot

# ---------------------------------
# Load Private Functions
# ---------------------------------

# Core config must load first
. $PSScriptRoot\Private\Get-RipClipConfig.ps1

$privatePath = Join-Path $PSScriptRoot 'Private'

if (Test-Path $privatePath) {
    Get-ChildItem -Path $privatePath -Filter *.ps1 |
        Where-Object { $_.Name -ne 'Get-RipClipConfig.ps1' } |
        ForEach-Object { . $_.FullName }
}

# ---------------------------------
# Load Public Functions
# ---------------------------------
# NOTE:
# Public functions are dot-sourced before exports.
# Wildcard export in the manifest controls visibility.

$publicPath = Join-Path $PSScriptRoot 'Public'

if (Test-Path $publicPath) {
    Get-ChildItem -Path $publicPath -Filter *.ps1 | ForEach-Object {
        . $_.FullName
    }
}

# ---------------------------------
# Initialize Configuration
# ---------------------------------

$script:RipClipConfig = Get-RipClipConfig

# =================================
# Internal Utility Functions
# =================================

function Add-RipClipLog {

    param(
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level,
        [string]$Message,
        [string]$Url
    )

    if (-not $script:RipClipConfig.Logging.Enabled) { return }

    try {

        $logRoot = if (-not [string]::IsNullOrWhiteSpace($script:RipClipConfig.Logging.CustomPath)) {
            $script:RipClipConfig.Logging.CustomPath
        }
        else {
            Join-Path (Join-Path $HOME '.ripclip') 'logs'
        }

        if (-not (Test-Path $logRoot)) {
            New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
        }

        $logFile = Join-Path $logRoot ("ripclip_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))

        [PSCustomObject]@{
            Timestamp = (Get-Date).ToString('o')
            Level     = $Level
            Url       = $Url
            Message   = $Message
            Version   = $script:RipClipConfig.Version
        } |
        ConvertTo-Json -Compress |
        Add-Content -Path $logFile -Encoding UTF8
    }
    catch {}
}

function Test-RipClipEnvironment {

    foreach ($tool in @(
        $script:RipClipConfig.Paths.YtDlp,
        $script:RipClipConfig.Paths.Ffmpeg
    )) {
        if (-not (Test-Path $tool)) {
            return $false
        }
    }

    return $true
}

function Get-RipClipRequest {

    param([string]$Url)

    $usingClipboard = [string]::IsNullOrWhiteSpace($Url)

    if ($usingClipboard) {
        $Url = Get-Clipboard

        if ([string]::IsNullOrWhiteSpace($Url)) {
            throw 'Clipboard is empty or does not contain a valid URL.'
        }

        $Url = ($Url -replace '&list=.*','')

        return @{
            Url           = $Url
            MaxItems      = 1
            ClipboardMode = $true
        }
    }

    if (-not [Uri]::IsWellFormedUriString($Url, [UriKind]::Absolute)) {
        throw 'Invalid URL format.'
    }

    $uri = [uri]$Url

    if ($uri.Host -notmatch '^(www\.)?(youtube\.com|youtu\.be)$') {
        throw 'Only YouTube URLs are supported.'
    }

    $isPlaylist = $Url -match '[\?&]list='

    if (-not $isPlaylist) {
        return @{
            Url           = $Url
            MaxItems      = 1
            ClipboardMode = $false
        }
    }

    Write-Host ''
    Write-Host 'Playlist detected.'

    $choice = Read-Host 'Download (A)ll, (N)umber of items, or (C)ancel?'

    switch ($choice.ToLower()) {

        'a' { return @{ Url=$Url; MaxItems=0; ClipboardMode=$false } }

        'n' {
            $count = Read-Host 'How many items?'
            if ($count -match '^\d+$') {
                return @{ Url=$Url; MaxItems=[int]$count; ClipboardMode=$false }
            }
            else { throw 'Invalid number.' }
        }

        default {
            Write-Host 'Cancelled.'
            return $null
        }
    }
}

function New-RipClipArguments {

    param(
        [string]$Url,
        [int]$MaxItems,
        [string]$OutputRoot
    )

    $OutputRoot = $OutputRoot.TrimEnd('\')
    $outputTemplate = "$OutputRoot\%(uploader)s\%(title)s.%(ext)s"

    $args = @(
        '-x'
        '--format','bestaudio/best'
        '--no-keep-video'
        '--audio-format',$script:RipClipConfig.Download.AudioFormat
        '--audio-quality',$script:RipClipConfig.Download.AudioQuality
    )

    if ($script:RipClipConfig.Download.EmbedThumbnail) {
        $args += '--embed-thumbnail'
    }

    if ($script:RipClipConfig.Download.AddMetadata) {
        $args += '--add-metadata'
    }

    $args += @(
        '--ffmpeg-location',$script:RipClipConfig.Paths.Ffmpeg
        '--output',$outputTemplate
    )

    if ($MaxItems -gt 0) {
        $args += '--playlist-items'
        $args += "1-$MaxItems"
    }

    if ($MaxItems -eq 1) {
        $args += '--no-playlist'
    }

    $args += $Url
    return $args
}

function Invoke-RipClipDownload {

    param([string[]]$Arguments)

    $outFile = Join-Path $env:TEMP 'ripclip_out.txt'
    $errFile = Join-Path $env:TEMP 'ripclip_err.txt'

    if (Test-Path $outFile) { Remove-Item $outFile -Force }
    if (Test-Path $errFile) { Remove-Item $errFile -Force }

    $process = Start-Process `
        -FilePath $script:RipClipConfig.Paths.YtDlp `
        -ArgumentList $Arguments `
        -NoNewWindow `
        -PassThru `
        -Wait `
        -RedirectStandardOutput $outFile `
        -RedirectStandardError  $errFile

    return [PSCustomObject]@{
        ExitCode = $process.ExitCode
        StdOut   = Get-Content $outFile -ErrorAction SilentlyContinue
        StdErr   = Get-Content $errFile -ErrorAction SilentlyContinue
        Success  = ($process.ExitCode -eq 0)
    }
}

function ConvertFrom-RipClipOutput {

    param($StdOut)

    if ($null -eq $StdOut) { return @() }

    if ($StdOut -isnot [System.Array]) {
        $StdOut = @($StdOut)
    }

    $paths = @()
    $audioExt = '.' + $script:RipClipConfig.Download.AudioFormat.ToLower()

    foreach ($line in $StdOut) {
        if ($line -match 'Destination:\s(.+)$') {
            $path = $matches[1].Trim()
            if ($path.ToLower().EndsWith($audioExt)) {
                $paths += $path
            }
        }
    }

    return @($paths)
}

# =================================
# Public Commands
# =================================

function Invoke-RipClip {
<#
.SYNOPSIS
Downloads audio from YouTube using yt-dlp with playlist awareness and safe defaults.
#>

    [CmdletBinding(DefaultParameterSetName='Download')]
    param(
        [Parameter(Position=0,ParameterSetName='Download')]
        [string]$Url,

        [Parameter(Position=1,ParameterSetName='Download')]
        [string]$OutputDirectory,

        [Parameter(ParameterSetName='Diagnostics')]
        [switch]$Diagnostics
    )

    if ($Diagnostics) {
        Write-Host ''
        Write-Host '=== RipClip Environment Diagnostics ===' -ForegroundColor Cyan
        Write-Host ''
        Write-Host "Version        : $($script:RipClipConfig.Version)"
        Write-Host "yt-dlp Exists  : $(Test-Path $script:RipClipConfig.Paths.YtDlp)"
        Write-Host "ffmpeg Exists  : $(Test-Path $script:RipClipConfig.Paths.Ffmpeg)"
        Write-Host ''
        return
    }

    if (-not (Test-RipClipEnvironment)) {
        throw 'Environment validation failed.'
    }

    try {
        if ($PSBoundParameters.ContainsKey('Url')) {

            if ($Url -eq '') {
                Write-Host ''
                Write-Host 'Empty string is not a valid URL.' -ForegroundColor Red
                Write-Host ''
                return
            }

            $request = Get-RipClipRequest -Url $Url
        }
        else {
            $request = Get-RipClipRequest -Url $null
        }
    }
    catch {
        Write-Host ''
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ''
        return
    }

    if ($null -eq $request) {
        Write-Host ''
        Write-Host 'Operation cancelled.' -ForegroundColor Yellow
        Write-Host ''
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $effectiveOutput = $OutputDirectory
    }
    elseif (-not [string]::IsNullOrWhiteSpace($script:RipClipConfig.Paths.OutputRoot)) {
        $effectiveOutput = $script:RipClipConfig.Paths.OutputRoot
    }
    else {
        $effectiveOutput = Join-Path (Join-Path $HOME 'Music') 'RipClip'
    }

    $effectiveOutput = $effectiveOutput.TrimEnd('\')

    if (-not (Test-Path $effectiveOutput)) {
        New-Item -ItemType Directory -Path $effectiveOutput -Force | Out-Null
    }

    $arguments = New-RipClipArguments `
        -Url $request.Url `
        -MaxItems $request.MaxItems `
        -OutputRoot $effectiveOutput

    $result = Invoke-RipClipDownload -Arguments $arguments
    $paths  = @(ConvertFrom-RipClipOutput -StdOut $result.StdOut)

    $total      = 0
    $downloaded = 0
    $skipped    = 0

    if ($result.Success) {

        $total = if ($request.MaxItems -gt 0) {
            $request.MaxItems
        }
        else {
            if ($paths.Count -gt 0) { $paths.Count } else { 1 }
        }

        $downloaded = $paths.Count
        $skipped    = $total - $downloaded

        foreach ($finalPath in $paths) {

            $fileName = Split-Path $finalPath -Leaf
            $artist   = Split-Path (Split-Path $finalPath -Parent) -Leaf

            Write-Host ''
            Write-Host '✔ Download Complete' -ForegroundColor Green
            Write-Host "Artist : $artist"
            Write-Host "File   : $fileName"
            Write-Host "Saved  : $finalPath"
        }
    }
    else {

        Write-Host ''
        Write-Host 'Download failed.' -ForegroundColor Red
        Write-Host "Exit Code: $($result.ExitCode)"
        Write-Host ''
    }

    $summaryColor = if ($downloaded -eq $total -and $total -gt 0) {
        'Green'
    }
    elseif ($downloaded -eq 0 -and $skipped -gt 0) {
        'Yellow'
    }
    else {
        'Cyan'
    }

    Write-Host ''
    Write-Host '=== Summary ===' -ForegroundColor $summaryColor
    Write-Host "Total      : $total" -ForegroundColor $summaryColor
    Write-Host "Downloaded : $downloaded" -ForegroundColor Green
    Write-Host "Skipped    : $skipped" -ForegroundColor Yellow
    Write-Host ''

    return [PSCustomObject]@{
        Url         = $request.Url
        ExitCode    = $result.ExitCode
        Success     = $result.Success
        OutputPaths = $paths
        OutputRoot  = $effectiveOutput
        Skipped     = ($skipped -gt 0)
    }
}

function Get-RipClipEffectiveConfig {
    Get-RipClipConfig | ConvertTo-Json -Depth 5
}

# ---------------------------------
# Public Aliases
# ---------------------------------

Set-Alias -Name rip -Value Invoke-RipClip -Scope Script