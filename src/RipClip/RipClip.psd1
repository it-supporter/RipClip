@{

    RootModule           = 'RipClip.psm1'
    ModuleVersion        = '0.7.0'
    CompatiblePSEditions = @('Core')

    GUID                 = 'fd942298-7f9c-4cc6-9f3d-8c7f3b09801b'

    Author               = 'Henrik Burchardt'
    CompanyName          = 'Reservehjernen'
    Copyright            = '(c) Henrik Burchardt. All rights reserved.'
    Description          = 'Modular PowerShell-based YouTube audio downloader built on yt-dlp with playlist control and clipboard integration.'
    PowerShellVersion    = '7.0'

    # RipClip currently exports its public surface explicitly via module structure.
    # Wildcard export keeps parity with PulseAI-Environment during active development.
    FunctionsToExport    = '*'

    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @(
        'rip'
    )

    PrivateData          = @{
        PSData = @{
            Tags = @(
                'PulseAI',
                'PowerShell',
                'yt-dlp',
                'YouTube',
                'CLI',
                'OpenSource'
            )

            LicenseUri   = 'https://github.com/it-supporter/RipClip/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/it-supporter/RipClip'
            ReleaseNotes = 'Structured architecture, JSON config layering, diagnostics support.'
        }
    }

}