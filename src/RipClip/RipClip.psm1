# =================================
# RipClip Module
# =================================

function Invoke-RipClip {

    [CmdletBinding()]
    param (
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
    }
}

# ---------------------------------
# Manual Wrapper (rip)
# ---------------------------------

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
