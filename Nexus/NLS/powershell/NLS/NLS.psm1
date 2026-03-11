# NLS - Nexus Ladder Scheduler Client Module
# Provides credential retrieval from the Nexus credential store

$script:NexusBaseUrl = $env:NEXUS_SERVER_URL
if (-not $script:NexusBaseUrl) { $script:NexusBaseUrl = 'http://localhost:8080' }

function Set-NLSServer {
    <#
    .SYNOPSIS
        Set the Nexus server URL for this session.
    .PARAMETER Url
        The base URL of the Nexus server (e.g. http://localhost:8080).
    .EXAMPLE
        Set-NLSServer -Url 'http://nexus-app:8080'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )
    $script:NexusBaseUrl = $Url.TrimEnd('/')
    Write-Verbose "NLS server set to $($script:NexusBaseUrl)"
}

function Get-NLSCredential {
    <#
    .SYNOPSIS
        Retrieve credentials from the Nexus credential store.
    .DESCRIPTION
        When a Name is specified, calls /api/credentials/<name>/resolve to fetch
        a single credential with all secret fields decrypted.
        When no Name is specified, calls /api/credentials to list all stored credentials (metadata only, no secrets).
    .PARAMETER Name
        The name of the credential to retrieve. If omitted, lists all credentials.
    .PARAMETER AsObject
        Return PSCustomObject(s) instead of hashtable(s).
    .EXAMPLE
        Get-NLSCredential
        # Returns all stored credentials (name, type, description)
    .EXAMPLE
        $creds = Get-NLSCredential -Name 'prod-db-login'
        $creds.username   # 'dbadmin'
        $creds.password   # 'supersecret'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name,

        [switch]$AsObject
    )

    # List all credentials when no name given
    if ([string]::IsNullOrWhiteSpace($Name)) {
        $url = "$($script:NexusBaseUrl)/api/credentials"
        try {
            $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
            if ($response.success -and $response.credentials) {
                if ($AsObject) {
                    return $response.credentials
                }
                $results = @()
                foreach ($cred in $response.credentials) {
                    $ht = @{}
                    foreach ($prop in $cred.PSObject.Properties) {
                        $ht[$prop.Name] = $prop.Value
                    }
                    $results += $ht
                }
                return $results
            }
            return @()
        } catch {
            throw "Failed to list credentials from Nexus: $($_.Exception.Message)"
        }
    }

    # Resolve a single credential
    $url = "$($script:NexusBaseUrl)/api/credentials/$([Uri]::EscapeDataString($Name))/resolve"

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop

        if ($response.success -and $response.credential -and $response.credential.values) {
            if ($AsObject) {
                return [PSCustomObject]$response.credential.values
            }

            # Convert PSCustomObject to hashtable
            $ht = @{}
            foreach ($prop in $response.credential.values.PSObject.Properties) {
                $ht[$prop.Name] = $prop.Value
            }
            return $ht
        } else {
            $msg = if ($response.message) { $response.message } else { "Failed to resolve credential '$Name'" }
            throw $msg
        }
    } catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        throw "Failed to retrieve credential '$Name' from Nexus: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Get-NLSCredential, Set-NLSServer
