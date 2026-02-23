function Invoke-RipClipReload {
<#
.SYNOPSIS
Reloads the RipClip module in the current session.
#>

    [CmdletBinding()]
    param()

    try {
        # ---------------------------------
        # Locate currently loaded module
        # ---------------------------------

        $loaded = Get-Module -Name RipClip -ErrorAction SilentlyContinue

        if ($loaded) {
            $modulePath = $loaded.Path
        }
        else {
            $modulePath = $null
        }

        # ---------------------------------
        # Remove existing instance (safe)
        # ---------------------------------

        Remove-Module -Name RipClip -Force -ErrorAction SilentlyContinue

        # ---------------------------------
        # Tier 1 — reload from original path
        # ---------------------------------

        if ($modulePath -and (Test-Path $modulePath)) {
            Import-Module -Name $modulePath -Force
            Write-Host "RipClip module reloaded." -ForegroundColor DarkGray
            return
        }

        # ---------------------------------
        # Tier 2 — repo discovery (PulseAI dev mode)
        # ---------------------------------

        $devManifest = Join-Path $HOME "Dev\RipClip\src\RipClip\RipClip.psd1"

        if (Test-Path $devManifest) {
            Import-Module -Name $devManifest -Force
            Write-Host "RipClip module reloaded." -ForegroundColor DarkGray
            return
        }

        # ---------------------------------
        # Tier 3 — PSModulePath fallback
        # ---------------------------------

        Import-Module -Name RipClip -Force
        Write-Host "RipClip module reloaded." -ForegroundColor DarkGray
    }
    catch {
        Write-Warning "[RipClip] Reload failed: $($_.Exception.Message)"
    }
}