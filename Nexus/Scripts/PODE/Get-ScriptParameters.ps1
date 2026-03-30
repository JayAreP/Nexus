# Parse script content and extract parameter definitions
# Returns: @{ success = $true; params = @( @{ name; mandatory; default } ) }
param(
    [Parameter(Mandatory)] [string]$Type,
    [Parameter(Mandatory)] [string]$Content
)

$result = @()

switch ($Type) {

    'powershell' {
        # Extract the param(...) block — handles multi-line and nested parens
        if ($Content -match '(?si)\bparam\s*\(') {
            $startIdx = $Content.IndexOf($Matches[0])
            $parenStart = $Content.IndexOf('(', $startIdx)
            if ($parenStart -ge 0) {
                $depth = 1
                $pos = $parenStart + 1
                while ($pos -lt $Content.Length -and $depth -gt 0) {
                    if ($Content[$pos] -eq '(') { $depth++ }
                    elseif ($Content[$pos] -eq ')') { $depth-- }
                    $pos++
                }
                $paramBlock = $Content.Substring($parenStart + 1, $pos - $parenStart - 2)

                # Split param block into individual parameter declarations by top-level commas
                # Track bracket/paren depth to avoid splitting on commas inside attributes
                $paramChunks = @()
                $chunkStart = 0
                $bracketDepth = 0
                $parenDepth = 0
                for ($ci = 0; $ci -lt $paramBlock.Length; $ci++) {
                    $ch = $paramBlock[$ci]
                    if ($ch -eq '[') { $bracketDepth++ }
                    elseif ($ch -eq ']') { $bracketDepth-- }
                    elseif ($ch -eq '(') { $parenDepth++ }
                    elseif ($ch -eq ')') { $parenDepth-- }
                    elseif ($ch -eq ',' -and $bracketDepth -eq 0 -and $parenDepth -eq 0) {
                        $paramChunks += $paramBlock.Substring($chunkStart, $ci - $chunkStart)
                        $chunkStart = $ci + 1
                    }
                }
                $paramChunks += $paramBlock.Substring($chunkStart)

                foreach ($chunk in $paramChunks) {
                    $chunk = $chunk.Trim()
                    # Must contain a $VarName to be a real parameter
                    if ($chunk -notmatch '\$(\w+)') { continue }

                    # Find the actual parameter variable (last $Word that isn't $true/$false/$null)
                    $varMatches = [regex]::Matches($chunk, '\$(\w+)')
                    $paramName = $null
                    foreach ($vm in $varMatches) {
                        $vn = $vm.Groups[1].Value
                        if ($vn -notin @('true', 'false', 'null')) {
                            $paramName = $vn
                        }
                    }
                    if (-not $paramName) { continue }

                    $isMandatory = $false
                    $defaultValue = ''
                    $paramType = ''
                    $validateSet = @()

                    # Check for [Parameter(Mandatory)] or [Parameter(Mandatory=$true)]
                    if ($chunk -match '(?i)\[Parameter\s*\([^\]]*Mandatory') {
                        $isMandatory = $true
                    }

                    # Extract type: [string], [int], [switch], [IPAddress], etc.
                    $typeMatches = [regex]::Matches($chunk, '\[(\w+)\]\s*\$' + [regex]::Escape($paramName))
                    if ($typeMatches.Count -gt 0) {
                        $paramType = $typeMatches[0].Groups[1].Value.ToLower()
                    }

                    # Extract ValidateSet values
                    if ($chunk -match '(?i)\[ValidateSet\s*\(([^\]]+)\)\]') {
                        $setBody = $Matches[1]
                        $setValues = [regex]::Matches($setBody, "'([^']*)'")
                        foreach ($sv in $setValues) {
                            $validateSet += $sv.Groups[1].Value
                        }
                    }

                    # Check for default value: $VarName = 'something' or $VarName = something
                    if ($chunk -match ('\$' + [regex]::Escape($paramName) + '\s*=\s*(.+)')) {
                        $defaultRaw = $Matches[1].Trim().TrimEnd(',').Trim()
                        # Strip surrounding quotes
                        if ($defaultRaw -match '^[''"](.*)[''"]\s*$') {
                            $defaultValue = $Matches[1]
                        } elseif ($defaultRaw -match '^\$(true|false|null)$') {
                            $defaultValue = $defaultRaw
                        } else {
                            $defaultValue = $defaultRaw
                        }
                    }

                    $entry = @{
                        name      = $paramName
                        mandatory = $isMandatory
                        default   = $defaultValue
                    }
                    if ($paramType) { $entry.type = $paramType }
                    if ($validateSet.Count -gt 0) { $entry.validateSet = $validateSet }
                    $result += $entry
                }
            }
        }
    }

    'shell' {
        # Find all $N references (positional parameters)
        $positions = [regex]::Matches($Content, '\$(\d+)') |
            ForEach-Object { [int]$_.Groups[1].Value } |
            Sort-Object -Unique
        foreach ($pos in $positions) {
            if ($pos -eq 0) { continue }  # $0 is the script itself
            $result += @{
                name      = "$pos"
                mandatory = $false
                default   = ''
            }
        }
    }

    'python' {
        # Strategy 1: Parse argparse add_argument calls
        # Matches: parser.add_argument('--name', ...) or add_argument('-n', '--name', ...)
        $argMatches = [regex]::Matches($Content, "(?i)add_argument\s*\(\s*(?:'[^']*'\s*,\s*)*'--(\w+)'([^)]*)\)")
        foreach ($m in $argMatches) {
            $paramName = $m.Groups[1].Value
            $argBody = $m.Groups[2].Value
            $isMandatory = $false
            $defaultValue = ''

            if ($argBody -match 'required\s*=\s*True') {
                $isMandatory = $true
            }
            if ($argBody -match "default\s*=\s*'([^']*)'") {
                $defaultValue = $Matches[1]
            } elseif ($argBody -match 'default\s*=\s*"([^"]*)"') {
                $defaultValue = $Matches[1]
            } elseif ($argBody -match 'default\s*=\s*(\S+)') {
                $val = $Matches[1].TrimEnd(',').Trim()
                if ($val -ne 'None') { $defaultValue = $val }
            }

            $result += @{
                name      = $paramName
                mandatory = $isMandatory
                default   = $defaultValue
            }
        }

        # Strategy 2: If no argparse found, check sys.argv[N]
        if ($result.Count -eq 0) {
            $sysArgvMatches = [regex]::Matches($Content, 'sys\.argv\[(\d+)\]')
            $positions = $sysArgvMatches | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique
            foreach ($pos in $positions) {
                if ($pos -eq 0) { continue }  # argv[0] is script name
                $result += @{
                    name      = "$pos"
                    mandatory = $false
                    default   = ''
                }
            }
        }
    }

    'terraform' {
        # Parse variable "name" { ... } blocks
        $varMatches = [regex]::Matches($Content, '(?si)variable\s+"(\w+)"\s*\{([^}]*)\}')
        foreach ($m in $varMatches) {
            $varName = $m.Groups[1].Value
            $varBody = $m.Groups[2].Value
            $defaultValue = ''
            $hasDefault = $false
            $varType = ''

            # Extract type = string|number|bool|list|map|object
            if ($varBody -match 'type\s*=\s*(\w+)') {
                $varType = $Matches[1].ToLower()
            }

            # Check for default = "value" or default = value
            if ($varBody -match 'default\s*=\s*"([^"]*)"') {
                $defaultValue = $Matches[1]
                $hasDefault = $true
            } elseif ($varBody -match "default\s*=\s*'([^']*)'") {
                $defaultValue = $Matches[1]
                $hasDefault = $true
            } elseif ($varBody -match 'default\s*=\s*(\S+)') {
                $defaultValue = $Matches[1]
                $hasDefault = $true
            }

            $entry = @{
                name      = $varName
                mandatory = (-not $hasDefault)
                default   = $defaultValue
            }
            if ($varType) { $entry.type = $varType }
            $result += $entry
        }
    }

    'armtemplate' {
        # Parse ARM template JSON parameters section
        try {
            $parsed = $Content | ConvertFrom-Json -ErrorAction Stop
        } catch {
            # Not valid JSON
            break
        }

        $parameters = $null
        if ($parsed.parameters) { $parameters = $parsed.parameters }
        elseif ($parsed.'$schema' -and $parsed.parameters) { $parameters = $parsed.parameters }

        if ($parameters) {
            foreach ($prop in $parameters.PSObject.Properties) {
                $paramName = $prop.Name
                $paramDef = $prop.Value
                $defaultValue = ''
                $hasDefault = $false
                $paramType = ''
                $validateSet = @()

                if ($paramDef.type) { $paramType = [string]$paramDef.type }
                if ($null -ne $paramDef.defaultValue) {
                    $defaultValue = [string]$paramDef.defaultValue
                    $hasDefault = $true
                }
                if ($paramDef.allowedValues) {
                    $validateSet = @($paramDef.allowedValues | ForEach-Object { [string]$_ })
                }

                $entry = @{
                    name      = $paramName
                    mandatory = (-not $hasDefault)
                    default   = $defaultValue
                }
                if ($paramType) { $entry.type = $paramType }
                if ($validateSet.Count -gt 0) { $entry.validateSet = $validateSet }
                # secureString / secureObject → password field
                if ($paramType -match '^secure') { $entry.type = 'password' }
                $result += $entry
            }
        }
    }

    'cloudformation' {
        # Parse CloudFormation YAML/JSON Parameters section
        # Strategy: try JSON first, then YAML
        $parsed = $null

        # JSON attempt
        try {
            $parsed = $Content | ConvertFrom-Json -ErrorAction Stop
        } catch { }

        if (-not $parsed) {
            # YAML attempt — requires powershell-yaml module or manual parsing
            # Use regex-based extraction for YAML Parameters block (robust, no module dependency)
            # Match each top-level parameter under the Parameters: key
            if ($Content -match '(?m)^Parameters:\s*$') {
                # Extract the Parameters block — everything between "Parameters:" and the next top-level key
                if ($Content -match '(?s)(?m)^Parameters:\s*\n(.*?)(?=\n\S|\z)') {
                    $paramBlock = $Matches[1]
                    # Split into individual parameter entries by lines starting with exactly 2 spaces + word
                    $paramEntries = [regex]::Matches($paramBlock, '(?m)^  (\w[\w\-]*):\s*\n((?:    .*\n?)*)')
                    foreach ($pe in $paramEntries) {
                        $paramName = $pe.Groups[1].Value
                        $paramBody = $pe.Groups[2].Value
                        $defaultValue = ''
                        $hasDefault = $false
                        $isMandatory = $true
                        $paramType = ''
                        $validateSet = @()

                        # Extract Type
                        if ($paramBody -match "(?m)^\s+Type:\s*['""]?(.+?)['""]?\s*$") {
                            $paramType = $Matches[1].Trim().Trim("'`"")
                        }

                        # Extract Default
                        if ($paramBody -match "(?m)^\s+Default:\s*['""]?(.*?)['""]?\s*$") {
                            $defaultValue = $Matches[1].Trim().Trim("'`"")
                            $hasDefault = $true
                            $isMandatory = $false
                        }

                        # Extract AllowedValues (YAML list)
                        if ($paramBody -match '(?s)AllowedValues:\s*\n((?:\s+-\s+.*\n?)*)') {
                            $avBlock = $Matches[1]
                            $avMatches = [regex]::Matches($avBlock, "(?m)^\s+-\s+['""]?(.*?)['""]?\s*$")
                            foreach ($av in $avMatches) {
                                $validateSet += $av.Groups[1].Value
                            }
                        }

                        # Extract NoEcho
                        $noEcho = $false
                        if ($paramBody -match '(?mi)^\s+NoEcho:\s*true') {
                            $noEcho = $true
                        }

                        $entry = @{
                            name      = $paramName
                            mandatory = $isMandatory
                            default   = $defaultValue
                        }
                        if ($paramType) { $entry.type = $paramType }
                        if ($validateSet.Count -gt 0) { $entry.validateSet = $validateSet }
                        if ($noEcho) { $entry.type = 'password' }
                        $result += $entry
                    }
                }
            }
        }

        if ($parsed) {
            # JSON CloudFormation template
            $parameters = $null
            if ($parsed.Parameters) {
                $parameters = $parsed.Parameters
            }
            if ($parameters) {
                foreach ($prop in $parameters.PSObject.Properties) {
                    $paramName = $prop.Name
                    $paramDef = $prop.Value
                    $defaultValue = ''
                    $hasDefault = $false
                    $paramType = ''
                    $validateSet = @()

                    if ($paramDef.Type) { $paramType = [string]$paramDef.Type }
                    if ($null -ne $paramDef.Default) {
                        $defaultValue = [string]$paramDef.Default
                        $hasDefault = $true
                    }
                    if ($paramDef.AllowedValues) {
                        $validateSet = @($paramDef.AllowedValues | ForEach-Object { [string]$_ })
                    }

                    $entry = @{
                        name      = $paramName
                        mandatory = (-not $hasDefault)
                        default   = $defaultValue
                    }
                    if ($paramType) { $entry.type = $paramType }
                    if ($validateSet.Count -gt 0) { $entry.validateSet = $validateSet }
                    if ($paramDef.NoEcho -eq $true) { $entry.type = 'password' }
                    $result += $entry
                }
            }
        }
    }
}

return @{
    success = $true
    params  = @($result)
}
