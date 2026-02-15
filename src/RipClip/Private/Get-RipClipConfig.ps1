function Get-RipClipConfig {

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $defaultConfigPath = Join-Path $moduleRoot "Config\ripclip.config.json"

    if (-not (Test-Path $defaultConfigPath)) {
        throw "Default configuration file not found."
    }

    $defaultConfig = Get-Content $defaultConfigPath -Raw | ConvertFrom-Json

    $userConfigDir = Join-Path $HOME ".ripclip"
    $userConfigPath = Join-Path $userConfigDir "config.json"

    if (Test-Path $userConfigPath) {

        $userConfig = Get-Content $userConfigPath -Raw | ConvertFrom-Json

        foreach ($section in $userConfig.PSObject.Properties) {

            if ($defaultConfig.$($section.Name)) {

                foreach ($prop in $section.Value.PSObject.Properties) {
                    $defaultConfig.$($section.Name).$($prop.Name) = $prop.Value
                }
            }
        }
    }

    return $defaultConfig
}
