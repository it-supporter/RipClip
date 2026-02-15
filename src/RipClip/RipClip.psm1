<<<<<<< Updated upstream
# =================================
# RipClip Module
# =================================
=======
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region Configuration

$Script:RipClipConfig = @{
    Paths = @{
        YtDlp      = "C:\Ripper\yt-dlp.exe"
        Ffmpeg     = "C:\Ripper\ffmpeg.exe"
        OutputRoot = "C:\Ripped"
    }

    Download = @{
        AudioFormat  = "mp3"
        AudioQuality = "0"
    }

    Logging = @{
        Enabled = $true
        LogRoot = "C:\Ripped\logs"
    }

    Version = "0.4.1-dev"
}

#endregion

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

        # Force single-video behavior from clipboard
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
            Url            = $Url
            MaxItems       = 1
            ClipboardMode  = $false
        }
    }

    Write-Host ""
    Write-Host "Playlist detected."

    $choice = Read-Host "Download (A)ll, (N)umber of items, or (C)ancel?"

    switch ($choice.ToLower()) {

        "a" {
            return @{
                Url            = $Url
                MaxItems       = 0
                ClipboardMode  = $false
            }
        }

        "n" {
            $count = Read-Host "How many items?"
            if ($count -match "^\d+$") {
                return @{
                    Url            = $Url
                    MaxItems       = [int]$count
                    ClipboardMode  = $false
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

#region Diagnostics

function Get-RipClipDiagnostics {

    param(
        $Request,
        $Arguments,
        $Result,
        [timespan]$Duration
    )

    return [PSCustomObject]@{
        Timestamp      = (Get-Date)
        RipClipVersion = $Script:RipClipConfig.Version
        Url            = $Request.Url
        MaxItems       = $Request.MaxItems
        ClipboardMode  = $Request.ClipboardMode
        YtDlpPath      = $Script:RipClipConfig.Paths.YtDlp
        FfmpegPath     = $Script:RipClipConfig.Paths.Ffmpeg
        ExitCode       = $Result.ExitCode
        Success        = $Result.Success
        DurationMS     = [int]$Duration.TotalMilliseconds
        Arguments      = ($Arguments -join " ")
        StdErr         = ($Result.StdErr -join "`n")
    }
}

#endregion

#region Public Entry
>>>>>>> Stashed changes

function Invoke-RipClip {

    [CmdletBinding(DefaultParameterSetName="Download")]
    param (
<<<<<<< Updated upstream
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Url,

        [switch]$Open
    )

    Write-Host ""
    Write-Host "RipClip processing..." -ForegroundColor Cyan

    # ---------------------------------
    # Validate yt-dlp
    # ---------------------------------

    if (-not (Get-Command yt-dlp -ErrorAction SilentlyContinue)) {
        Write-Host "yt-dlp not found in PATH." -ForegroundColor Red
        return
    }

    # ---------------------------------
    # Detect Playlist
    # ---------------------------------

    $IsPlaylist = $Url -match "list="
    $PlaylistLimit = $null

    if ($IsPlaylist) {

        Write-Host ""
        Write-Host "Playlist detected." -ForegroundColor Yellow

        $InputCount = Read-Host "How many items to download? (Press Enter for all)"

        if ($InputCount -and $InputCount -match '^\d+$') {
            $PlaylistLimit = [int]$InputCount
        }
        elseif ($InputCount) {
            Write-Host "Invalid input. Downloading full playlist." -ForegroundColor DarkYellow
        }
    }

    # ---------------------------------
    # Define Output Folder
    # ---------------------------------

    $OutputFolder = Join-Path $HOME "Music"

    if (-not (Test-Path $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder | Out-Null
    }

    # ---------------------------------
    # Build yt-dlp Arguments
    # ---------------------------------

    $Arguments = @(
        "--extract-audio"
        "--audio-format", "mp3"
        "--print", "after_move:filepath"
        "-o", "$OutputFolder\%(title)s.%(ext)s"
        $Url
    )

    if ($PlaylistLimit) {
        $Arguments += @("--playlist-end", $PlaylistLimit)
    }

    # ---------------------------------
    # Execute yt-dlp
    # ---------------------------------

    try {
        $Result = & yt-dlp @Arguments 2>&1
    }
    catch {
        Write-Host "yt-dlp execution failed." -ForegroundColor Red
        return
    }

    # ---------------------------------
    # Extract Final File Paths (FIXED)
    # ---------------------------------

    $FullPaths = $Result | Where-Object { $_ -match "^[A-Za-z]:\\" }

    if ($FullPaths -and $FullPaths.Count -gt 0) {

        Write-Host ""
        Write-Host "Download completed." -ForegroundColor Green
        Write-Host "Saved as:" -ForegroundColor DarkGray

        foreach ($Path in $FullPaths) {
            Write-Host $Path -ForegroundColor Cyan
        }

        Write-Host ""

        if ($Open) {
            foreach ($Path in $FullPaths) {
                if (Test-Path $Path) {
                    Start-Process explorer.exe "/select,`"$Path`""
                }
            }
        }
    }
    else {
        Write-Host ""
        Write-Host "Download finished, but file path could not be detected." -ForegroundColor Yellow
        Write-Host ""
=======
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
>>>>>>> Stashed changes
    }
}

# ---------------------------------
# Manual Wrapper (rip)
# ---------------------------------

<<<<<<< Updated upstream
function rip {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Url,

        [switch]$Open
    )

    Invoke-RipClip -Url $Url -Open:$Open
}

# ---------------------------------
# Clipboard Wrapper (ripclip)
# ---------------------------------

function ripclip {
    param(
        [switch]$Open
    )

    if (-not (Get-Command Get-Clipboard -ErrorAction SilentlyContinue)) {
        Write-Host "Clipboard access not available." -ForegroundColor Red
        return
    }

    $ClipboardContent = Get-Clipboard

    if (-not $ClipboardContent) {
        Write-Host "Clipboard is empty." -ForegroundColor Yellow
        return
    }

    if ($ClipboardContent -notmatch "^https?://") {
        Write-Host "Clipboard does not contain a valid URL." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "Using URL from clipboard:" -ForegroundColor DarkGray
    Write-Host $ClipboardContent -ForegroundColor Cyan

    Invoke-RipClip -Url $ClipboardContent -Open:$Open
}

Export-ModuleMember -Function Invoke-RipClip, rip, ripclip
=======
Set-Alias rip Invoke-RipClip
Export-ModuleMember -Function Invoke-RipClip -Alias rip
>>>>>>> Stashed changes
