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
}

#endregion

#region Private Functions

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
            New-Item -ItemType Directory -Path $Script:RipClipConfig.Paths.OutputRoot -Force | Out-Null
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

    return @(
        "-x"
        "--audio-format",  $Script:RipClipConfig.Download.AudioFormat
        "--audio-quality", $Script:RipClipConfig.Download.AudioQuality
        "--embed-thumbnail"
        "--add-metadata"
        "--no-check-formats"
        "--ffmpeg-location", $Script:RipClipConfig.Paths.Ffmpeg
        "--output", "$($Script:RipClipConfig.Paths.OutputRoot)\%(playlist_title)s\%(title)s.%(ext)s"
        $Url
    )
}

#endregion

#region Public Functions

function Invoke-RipClip {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Url
    )

    $envTest = Test-RipClipEnvironment

    if (-not $envTest.Success) {
        throw "Environment validation failed. Missing: $($envTest.Missing -join ', ')"
    }

    $arguments = Build-RipClipArguments -Url $Url

    return [PSCustomObject]@{
        Url       = $Url
        Arguments = $arguments
        Status    = "Arguments built"
        Success   = $true
    }
}

#endregion

Export-ModuleMember -Function Invoke-RipClip
