function Update-RipClip {
<#
.SYNOPSIS
Reloads the RipClip module.
#>

    [CmdletBinding()]
    param()

    # Public UX wrapper for the internal reload engine
    Invoke-RipClipReload @PSBoundParameters
}