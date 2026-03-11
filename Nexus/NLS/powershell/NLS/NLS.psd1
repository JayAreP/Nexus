@{
    RootModule        = 'NLS.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a3b7c8d9-1234-5678-abcd-ef0123456789'
    Author            = 'Nexus'
    CompanyName       = 'Nexus Automation'
    Description       = 'NLS (Nexus Ladder Scheduler) - Client module for Nexus credential store and utilities'
    FunctionsToExport = @('Get-NLSCredential', 'Set-NLSServer')
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
    PowerShellVersion  = '7.0'
}
