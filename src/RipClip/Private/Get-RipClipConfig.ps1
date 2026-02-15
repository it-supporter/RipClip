function Get-RipClipConfig {

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $defaultConfigPath = Join-Path $moduleRoot "Config\ripclip.config.json"

    if (-not (Test-Path $defaultConfigPath)) {
        throw "Default configuration file not found."
    }

    $defaultConfig = Get-Content $defaultConfigPath -Raw | ConvertFrom-Json

    $userConfigDir  = Join-Path $HOME ".ripclip"
    $userConfigPath = Join-Path $userConfigDir "config.json"

    # Ensure user config directory exists
    if (-not (Test-Path $userConfigDir)) {
        New-Item -ItemType Directory -Path $userConfigDir -Force | Out-Null
    }

    # Bootstrap user config if missing
    if (-not (Test-Path $userConfigPath)) {

        $defaultConfig | ConvertTo-Json -Depth 5 |
            Set-Content -Path $userConfigPath -Encoding UTF8

        Write-Host ""
        Write-Host "RipClip user configuration initialized at:" -ForegroundColor Cyan
        Write-Host $userConfigPath -ForegroundColor DarkGray
        Write-Host ""
    }
    else {

        $userConfig = Get-Content $userConfigPath -Raw | ConvertFrom-Json

        foreach ($section in $userConfig.PSObject.Properties) {

            if ($defaultConfig.PSObject.Properties.Name -contains $section.Name) {

                $defaultSection = $defaultConfig.$($section.Name)
                $userSection    = $section.Value

                if ($defaultSection -is [PSCustomObject]) {

                    foreach ($prop in $userSection.PSObject.Properties) {

                        if ($defaultSection.PSObject.Properties.Name -contains $prop.Name) {
                            $defaultSection.$($prop.Name) = $prop.Value
                        }
                    }
                }
                else {
                    $defaultConfig.$($section.Name) = $userSection
                }
            }
        }
    }

    . $PSScriptRoot\Test-RipClipConfig.ps1
    Test-RipClipConfig -Config $defaultConfig | Out-Null

    return $defaultConfig
}
