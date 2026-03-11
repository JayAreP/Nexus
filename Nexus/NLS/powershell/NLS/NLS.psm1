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
        Retrieve decrypted credentials from the Nexus credential store.
    .DESCRIPTION
        Calls the Nexus /api/credentials/<name>/resolve endpoint to fetch
        a named credential with all secret fields decrypted. Returns a
        hashtable of the credential values.
    .PARAMETER Name
        The name of the credential to retrieve.
    .PARAMETER AsObject
        Return a PSCustomObject instead of a hashtable.
    .EXAMPLE
        $creds = Get-NLSCredential -Name 'prod-db-login'
        $creds.username   # 'dbadmin'
        $creds.password   # 'supersecret'
    .EXAMPLE
        $sp = Get-NLSCredential -Name 'azure-sp-prod'
        Connect-AzAccount -ServicePrincipal -TenantId $sp.tenantId `
            -ApplicationId $sp.clientId `
            -Credential (New-Object PSCredential $sp.clientId, (ConvertTo-SecureString $sp.clientSecret -AsPlainText -Force))
    .EXAMPLE
        $aws = Get-NLSCredential -Name 'aws-production'
        Set-AWSCredential -AccessKey $aws.accessKeyId -SecretKey $aws.secretAccessKey -StoreAs default
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [switch]$AsObject
    )

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
