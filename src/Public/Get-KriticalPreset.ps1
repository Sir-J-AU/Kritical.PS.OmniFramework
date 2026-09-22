function Get-KriticalPreset {
    <#
    .SYNOPSIS
    Lists all registered presets, optionally filtered by command, parameter, or name.

    .DESCRIPTION
    Get-KriticalPreset queries PSFramework configuration to retrieve all previously
    registered presets (stored by Register-KriticalPreset). Presets can be filtered
    by command name, parameter name, or preset name to narrow results.

    .PARAMETER Command
    Filter presets to only those registered for a specific command.
    Optional. Examples: 'Start-KritEtwCapture', 'Invoke-KritDistributedCapture'.

    .PARAMETER Parameter
    Filter presets to only those registered for a specific parameter.
    Optional. Examples: 'Provider', 'ComputerName'.

    .PARAMETER Name
    Filter presets to only those with a specific preset name.
    Optional. Examples: 'CpuSpike', 'HighMemory'.

    .OUTPUTS
    [PSCustomObject] One object per matching preset with properties:
      - Name: The preset name
      - Command: The command this preset is registered for
      - Parameter: The parameter this preset is registered for
      - Value: The preset's stored value
      - Description: The preset's description (if provided)

    .EXAMPLE
    # List all presets
    Get-KriticalPreset

    .EXAMPLE
    # List presets for the Start-KritEtwCapture command only
    Get-KriticalPreset -Command Start-KritEtwCapture

    .EXAMPLE
    # List presets for the Provider parameter only
    Get-KriticalPreset -Parameter Provider

    .EXAMPLE
    # Retrieve a specific preset by name
    Get-KriticalPreset -Name 'CpuSpike'

    .NOTES
    Queries PSFramework config keys under 'Kritical.Presets.*' to build the result set.
    Filters are applied after querying, so all keys matching the pattern are read.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]
        $Command,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]
        $Parameter,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]
        $Name
    )

    # Query all preset configs from PSFramework
    $allPresets = Get-PSFConfig -FullName 'Kritical.Presets.*' -ErrorAction SilentlyContinue

    if (-not $allPresets) {
        return
    }

    # Normalize to array
    if ($allPresets -isnot [array]) {
        $allPresets = @($allPresets)
    }

    # Parse each config key and build preset objects
    $results = @()
    foreach ($config in $allPresets) {
        $fullName = $config.FullName
        # Skip description entries (handled separately)
        if ($fullName -match '\.Description$') {
            continue
        }

        # Parse the key: Kritical.Presets.<Command>.<Parameter>.<Name> [.Description]
        # Extract: Kritical.Presets.{Command}.{Parameter}.{Name}
        if ($fullName -match '^Kritical\.Presets\.(.+)\.(.+)\.(.+)$') {
            $configCommand = $Matches[1]
            $configParameter = $Matches[2]
            $configName = $Matches[3]

            # Apply filters
            if ($Command -and $configCommand -ne $Command) {
                continue
            }
            if ($Parameter -and $configParameter -ne $Parameter) {
                continue
            }
            if ($Name -and $configName -ne $Name) {
                continue
            }

            # Retrieve the description if it exists
            $descKey = "$fullName.Description"
            $descConfig = Get-PSFConfig -FullName $descKey -ErrorAction SilentlyContinue
            $description = if ($descConfig) { $descConfig.Value } else { $null }

            $results += [PSCustomObject]@{
                Name        = $configName
                Command     = $configCommand
                Parameter   = $configParameter
                Value       = $config.Value
                Description = $description
            }
        }
    }

    return $results
}
