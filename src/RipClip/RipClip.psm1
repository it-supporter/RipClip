Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load configuration engine
. $PSScriptRoot\Private\Get-RipClipConfig.ps1
$Script:RipClipConfig = Get-RipClipConfig

#region Logging

function Write-RipClipLog {
    param(
        [ValidateSet("INFO","WARN","ERROR")]
        [string]$Level,
        [string]$Message,
        [string]$Url
    )

    if (-not $Script:RipClipConfig.Logging.Enabled) { return }

    try {
        if (-not (Test-Path $Script:RipClipConfig.Logging.LogRoot)) {
            New-Item -ItemType Directory -Path $Script:RipClipConfig.Logging.LogRoot -Force | Out-Null
        }

        $logFile = Join-Path $Script:RipClipConfig.Logging.LogRoot `
            ("ripclip_{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))

        [PSCustomObject]@{
            Timestamp = (Get-Date).ToString("o")
            Level     = $Level
            Url       = $Url
            Message   = $Message
            Version   = $Script:RipClipConfig.Version
        } | ConvertTo-Json -Compress |
            Add-Content -Path $logFile
    }
    catch {}
}

#endregion

#region Environment

function Test-RipClipEnvironment {

    foreach ($tool in @(
        $Script:RipClipConfig.Paths.YtDlp,
        $Script:RipClipConfig.Paths.Ffmpeg
    )) {
        if (-not (Test-Path $tool)) {
            return $false
        }
    }

    if (-not (Test-Path $Script:RipClipConfig.Paths.OutputRoot)) {
        New-Item -ItemType Directory -Path $Script:RipClipConfig.Paths.OutputRoot -Force | Out-Null
    }

    return $true
}

#endregion

#region Policy Layer

function Resolve-RipClipRequest {

    param([string]$Url)

    $usingClipboard = [string]::IsNullOrWhiteSpace($Url)

    if ($usingClipboard) {

        $Url = Get-Clipboard

        if ([string]::IsNullOrWhiteSpace($Url)) {
            throw "Clipboard is empty or does not contain a valid URL."
        }

        $Url = ($Url -replace "&list=.*","")

        return @{
            Url           = $Url
            MaxItems      = 1
            ClipboardMode = $true
        }
    }

    if (-not [Uri]::IsWellFormedUriString($Url, [UriKind]::Absolute)) {
        throw "Invalid URL format."
    }

    $uri = [uri]$Url
    if ($uri.Host -notmatch "^(www\.)?(youtube\.com|youtu\.be)$") {
        throw "Only YouTube URLs are supported."
    }

    $isPlaylist = $Url -match "[\?&]list="

    if (-not $isPlaylist) {
        return @{
            Url           = $Url
            MaxItems      = 1
            ClipboardMode = $false
        }
    }

    Write-Host ""
    Write-Host "Playlist detected."

    $choice = Read-Host "Download (A)ll, (N)umber of items, or (C)ancel?"

    switch ($choice.ToLower()) {

        "a" {
            return @{
                Url           = $Url
                MaxItems      = 0
                ClipboardMode = $false
            }
        }

        "n" {
            $count = Read-Host "How many items?"
            if ($count -match "^\d+$") {
                return @{
                    Url           = $Url
                    MaxItems      = [int]$count
                    ClipboardMode = $false
                }
            }
            else { throw "Invalid number." }
        }

        default {
            Write-Host "Cancelled."
            return $null
        }
    }
}

#endregion

#region Engine Layer

function Build-RipClipArguments {

    param(
        [string]$Url,
        [int]$MaxItems
    )

    $outputTemplate = "$($Script:RipClipConfig.Paths.OutputRoot)\%(uploader)s\%(title)s.%(ext)s"

    $args = @(
        "-x"
        "--format", "bestaudio/best"
        "--no-keep-video"
        "--audio-format",  $Script:RipClipConfig.Download.AudioFormat
        "--audio-quality", $Script:RipClipConfig.Download.AudioQuality
        "--embed-thumbnail"
        "--add-metadata"
        "--ffmpeg-location", $Script:RipClipConfig.Paths.Ffmpeg
        "--output", $outputTemplate
    )

    if ($MaxItems -gt 0) {
        $args += "--playlist-items"
        $args += "1-$MaxItems"
    }

    if ($MaxItems -eq 1) {
        $args += "--no-playlist"
    }

    $args += $Url

    return $args
}

function Invoke-RipClipDownload {

    param([string[]]$Arguments)

    $outFile = Join-Path $env:TEMP "ripclip_out.txt"
    $errFile = Join-Path $env:TEMP "ripclip_err.txt"

    if (Test-Path $outFile) { Remove-Item $outFile -Force }
    if (Test-Path $errFile) { Remove-Item $errFile -Force }

    $process = Start-Process `
        -FilePath $Script:RipClipConfig.Paths.YtDlp `
        -ArgumentList $Arguments `
        -NoNewWindow `
        -PassThru `
        -Wait `
        -RedirectStandardOutput $outFile `
        -RedirectStandardError  $errFile

    $stdout = Get-Content $outFile -ErrorAction SilentlyContinue
    $stderr = Get-Content $errFile -ErrorAction SilentlyContinue

    return [PSCustomObject]@{
        ExitCode = $process.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
        Success  = ($process.ExitCode -eq 0)
    }
}

function Parse-RipClipOutput {

    param($StdOut)

    if ($StdOut -isnot [System.Array]) {
        $StdOut = @($StdOut)
    }

    $paths = @()

    foreach ($line in $StdOut) {
        if ($line -match "Destination:\s(.+)$") {
            $path = $matches[1]
            if ($path.ToLower().EndsWith(".$($Script:RipClipConfig.Download.AudioFormat.ToLower())")) {
                $paths += $path
            }
        }
    }

    return $paths
}

#endregion

#region Public Entry

function Invoke-RipClip {

    [CmdletBinding(DefaultParameterSetName="Download")]
    param (
        [Parameter(Position=0, ParameterSetName="Download")]
        [string]$Url,

        [Parameter(ParameterSetName="Diagnostics")]
        [switch]$Diagnostics
    )

    if ($Diagnostics) {

        Write-Host ""
        Write-Host "=== RipClip Environment Diagnostics ===" -ForegroundColor Cyan
        Write-Host ""

        Write-Host "Version        : $($Script:RipClipConfig.Version)"
        Write-Host "yt-dlp Exists  : $(Test-Path $Script:RipClipConfig.Paths.YtDlp)"
        Write-Host "ffmpeg Exists  : $(Test-Path $Script:RipClipConfig.Paths.Ffmpeg)"
        Write-Host "Output Exists  : $(Test-Path $Script:RipClipConfig.Paths.OutputRoot)"
        Write-Host ""
        return
    }

    if (-not (Test-RipClipEnvironment)) {
        throw "Environment validation failed."
    }

    $request = Resolve-RipClipRequest -Url $Url
    if (-not $request) { return }

    Write-RipClipLog -Level INFO -Message "Invocation started." -Url $request.Url

    $arguments = Build-RipClipArguments `
        -Url $request.Url `
        -MaxItems $request.MaxItems

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-RipClipDownload -Arguments $arguments
    $sw.Stop()

    $paths = @()

    if ($result.Success) {
        $paths = Parse-RipClipOutput -StdOut $result.StdOut
    }

    foreach ($finalPath in $paths) {

        $fileName = Split-Path $finalPath -Leaf
        $artist   = Split-Path (Split-Path $finalPath -Parent) -Leaf

        Write-Host ""
        Write-Host "✔ Download Complete" -ForegroundColor Green
        Write-Host "Artist : $artist"
        Write-Host "File   : $fileName"
        Write-Host "Saved  : $finalPath"
    }

    if (-not $result.Success) {

        $diag = Get-RipClipDiagnostics `
            -Request $request `
            -Arguments $arguments `
            -Result $result `
            -Duration $sw.Elapsed

        Write-Host ""
        Write-Host "=== RipClip Diagnostics ===" -ForegroundColor Yellow
        $diag | Format-List
        Write-Host ""
    }

    return [PSCustomObject]@{
        Url         = $request.Url
        ExitCode    = $result.ExitCode
        Success     = $result.Success
        OutputPaths = $paths
    }
}

#endregion

Set-Alias rip Invoke-RipClip
Export-ModuleMember -Function Invoke-RipClip -Alias rip
