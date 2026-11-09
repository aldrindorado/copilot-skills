param([string]$Engine, [string]$ParameterFile)
$ErrorActionPreference = 'Stop'
try {
    $parameters = @{}
    $data = Get-Content -LiteralPath $ParameterFile -Raw | ConvertFrom-Json
    foreach ($property in $data.PSObject.Properties) {
        $parameters[$property.Name] = $property.Value
    }
    & $Engine @parameters
}
catch {
    Write-Output $_.Exception.Message
    exit 1
}
