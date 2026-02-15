function Test-RipClipConfig {

    param($Config)

    # Ensure top-level Paths section exists
    # This section defines core executable locations and output behavior.
    if (-not $Config.Paths) {
        throw "Configuration error: 'Paths' section missing."
    }

    # yt-dlp executable path is mandatory.
    # Without it, RipClip cannot perform downloads.
    if (-not $Config.Paths.YtDlp) {
        throw "Configuration error: 'Paths.YtDlp' missing."
    }

    # ffmpeg path is mandatory for audio extraction and metadata embedding.
    if (-not $Config.Paths.Ffmpeg) {
        throw "Configuration error: 'Paths.Ffmpeg' missing."
    }

    # OutputRoot is optional (Design B philosophy).
    # If undefined, we normalize it to an empty string
    # so runtime fallback logic can take over.
    if ($null -eq $Config.Paths.OutputRoot) {
        $Config.Paths.OutputRoot = ""
    }

    # Ensure Download section exists.
    # This controls format, quality, and feature toggles.
    if (-not $Config.Download) {
        throw "Configuration error: 'Download' section missing."
    }

    # AudioFormat is mandatory.
    # The engine must know which format to request from yt-dlp.
    if (-not $Config.Download.AudioFormat) {
        throw "Configuration error: 'Download.AudioFormat' missing."
    }

    # Logging section must exist even if disabled.
    # Prevents null reference issues later.
    if (-not $Config.Logging) {
        throw "Configuration error: 'Logging' section missing."
    }

    # Logging.Enabled must be explicitly boolean.
    # Prevents accidental string values like "true".
    if ($Config.Logging.Enabled -isnot [bool]) {
        throw "Configuration error: 'Logging.Enabled' must be true or false."
    }

    return $true
}
