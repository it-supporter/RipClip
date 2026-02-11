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

    Version = "0.3.0-dev"
}

#endregion

#region Private Functions

function Write-RipClipLog {

    param(
        [Parameter(Mandatory)]
        [ValidateSet("INFO","WARN","ERROR")]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Url
    )

    if (-not $Script:RipClipConfig.Logging.Enabled) {
        return
    }

    try {
        if (-not (Test-Path $Script:RipClipConfig.Logging.LogRoot)) {
            New-Item -ItemType Directory `
                -Path $Script:RipClipConfig.Logging.LogRoot `
                -Force | Out-Null
        }

        $logFile = Join-Path `
            $Script:RipClipConfig.Logging.LogRoot `
            ("ripclip_{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))

        $entry = [PSCustomObject]@{
            Timestamp = (Get-Date).ToString("o")
            Level     = $Level
            Url       = $Url
            Message   = $Message
            Version   = $Script:RipClipConfig.Version
        }

        $entry |
            ConvertTo-Json -Compress |
            Add-Content -Path $logFile
    }
    catch {
        # Logging must never interrupt execution
    }
}

function Test-RipClipEnvironment {

    $missing = @()

    foreach ($tool in @(
        $Script:RipClipConfig.Paths.YtDlp,
        $Script:RipClipConfig.Paths.Ffmpeg
    )) {
        if (-not (Test-Path $tool)) {
            $missing += $tool
        }
    }

    if (-not (Test-Path $Script:RipClipConfig.Paths.OutputRoot)) {
        try {
            New-Item -ItemType Directory `
                -Path $Script:RipClipConfig.Paths.OutputRoot `
                -Force | Out-Null
        }
        catch {
            $missing += "Output directory creation failed"
        }
    }

    return [PSCustomObject]@{
        Success = ($missing.Count -eq 0)
        Missing = $missing
    }
}

function Build-RipClipArguments {

    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    $isPlaylist = $Url -match "[\?&]list="

    $args = @(
        "-x"
        "--audio-format",  $Script:RipClipConfig.Download.AudioFormat
        "--audio-quality", $Script:RipClipConfig.Download.AudioQuality
        "--embed-thumbnail"
        "--add-metadata"
        "--ffmpeg-location", $Script:RipClipConfig.Paths.Ffmpeg
        "--output", "$($Script:RipClipConfig.Paths.OutputRoot)\%(artist,creator,uploader)s\%(artist,creator,uploader)s - %(title)s.%(ext)s"
    )

    if (-not $isPlaylist) {
        $args += "--no-playlist"
    }

    $args += $Url

    return $args
}

function Invoke-RipClipDownload {

    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $stdout   = $null
    $stderr   = $null
    $exitCode = 0

    try {
        $stdout   = & $Script:RipClipConfig.Paths.YtDlp @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    catch {
        $stderr   = $_.Exception.Message
        $exitCode = 1
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        StdOut   = $stdout
        StdErr   = $stderr
        Success  = ($exitCode -eq 0)
    }
}

#endregion

#region Public Functions

function Invoke-RipClip {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Url
    )

    # ---------------------------
    # Defensive Input Validation
    # ---------------------------

    if ([string]::IsNullOrWhiteSpace($Url)) {
        Write-RipClipLog -Level ERROR -Message "URL was empty or whitespace." -Url $Url
        throw "URL cannot be empty."
    }

    if (-not [Uri]::IsWellFormedUriString($Url, [UriKind]::Absolute)) {
        Write-RipClipLog -Level ERROR -Message "Invalid URL format." -Url $Url
        throw "Invalid URL format."
    }

    $uri = [uri]$Url

    if ($uri.Host -notmatch "^(www\.)?(youtube\.com|youtu\.be)$") {
        Write-RipClipLog -Level ERROR -Message "URL host is not a valid YouTube domain." -Url $Url
        throw "Only YouTube URLs are supported."
    }

    Write-RipClipLog -Level INFO -Message "Invocation started." -Url $Url

    # ---------------------------
    # Environment Validation
    # ---------------------------

    $envTest = Test-RipClipEnvironment

    if (-not $envTest.Success) {
        Write-RipClipLog -Level ERROR -Message "Environment validation failed." -Url $Url
        throw "Environment validation failed. Missing: $($envTest.Missing -join ', ')"
    }

    Write-RipClipLog -Level INFO -Message "Environment validation passed." -Url $Url

    # ---------------------------
    # Execution Pipeline
    # ---------------------------

    $arguments = Build-RipClipArguments -Url $Url
    $result    = Invoke-RipClipDownload -Arguments $arguments

    if ($result.Success) {
        Write-RipClipLog -Level INFO -Message "Download completed successfully." -Url $Url
    }
    else {

        $errMsg = if ([string]::IsNullOrWhiteSpace($result.StdErr)) {
            "Download failed with exit code $($result.ExitCode)."
        }
        else {
            $result.StdErr
        }

        Write-RipClipLog -Level ERROR -Message $errMsg -Url $Url
    }

    return [PSCustomObject]@{
        Url      = $Url
        ExitCode = $result.ExitCode
        Success  = $result.Success
        StdErr   = $result.StdErr
    }
}

#endregion

Export-ModuleMember -Function Invoke-RipClip
