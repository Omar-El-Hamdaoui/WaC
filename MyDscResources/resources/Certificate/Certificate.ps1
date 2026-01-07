using namespace System.Security.Cryptography.X509Certificates

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Get', 'Set', 'Test')]
    [string]$Operation
)

function Get-CertificateState {
    param($InputObject)
    
    # Extraire les valeurs avec des défauts
    $location = if ($InputObject.Location) { $InputObject.Location } else { 'LocalMachine' }
    $storeName = if ($InputObject.StoreName) { $InputObject.StoreName } else { 'Root' }
    $ensure = if ($InputObject.Ensure) { $InputObject.Ensure } else { 'Present' }
    $path = $InputObject.Path
    
    $fileCert = [X509Certificate2]::new($path)
    $thumbprint = $fileCert.Thumbprint

    $storeCert = Get-CertificateFromStore -Thumbprint $thumbprint -Location $location -StoreName $storeName
    $currentEnsure = $null -ne $storeCert ? 'Present' : 'Absent'

    return [PSCustomObject]@{
        Path = $path
        Thumbprint = $thumbprint
        Location = $location
        StoreName = $storeName
        Ensure = $currentEnsure
    }
}

function Test-CertificateState {
    param($InputObject)
    
    $ensure = if ($InputObject.Ensure) { $InputObject.Ensure } else { 'Present' }
    
    $current = Get-CertificateState -InputObject $InputObject
    return $current.Ensure -eq $ensure
}

function Set-CertificateState {
    param($InputObject)
    
    # Extraire les valeurs avec des défauts
    $location = if ($InputObject.Location) { $InputObject.Location } else { 'LocalMachine' }
    $storeName = if ($InputObject.StoreName) { $InputObject.StoreName } else { 'Root' }
    $ensure = if ($InputObject.Ensure) { $InputObject.Ensure } else { 'Present' }
    $path = $InputObject.Path
    
    $current = Get-CertificateState -InputObject $InputObject

    if ($ensure -eq 'Present' -and $current.Ensure -eq 'Absent') {
        Write-Verbose "Installing certificate with thumbprint $($current.Thumbprint) to $storeName store in $location location."
        Import-Certificate -FilePath $path -CertStoreLocation "Cert:\$location\$storeName" | Out-Null
    }
    elseif ($ensure -eq 'Absent' -and $current.Ensure -eq 'Present') {
        Write-Verbose "Removing certificate with thumbprint $($current.Thumbprint) from $storeName store in $location location."
        $cert = Get-CertificateFromStore -Thumbprint $current.Thumbprint -Location $location -StoreName $storeName
        if ($null -ne $cert) {
            Remove-Item $cert.PSPath -Force
        }
    }

    return Get-CertificateState -InputObject $InputObject
}

function Get-CertificateFromStore {
    param(
        [string]$Thumbprint,
        [string]$Location,
        [string]$StoreName
    )

    try {
        return Get-ChildItem -Path "Cert:\$Location\$StoreName\$Thumbprint" -ErrorAction Stop
    }
    catch {
        return $null
    }
}

# Main execution - Lecture depuis stdin
try {
    $jsonInput = [Console]::In.ReadToEnd()
    $inputObject = $jsonInput | ConvertFrom-Json

    $result = switch ($Operation) {
        'Get' { Get-CertificateState -InputObject $inputObject }
        'Test' { [PSCustomObject]@{ InDesiredState = Test-CertificateState -InputObject $inputObject } }
        'Set' { Set-CertificateState -InputObject $inputObject }
    }

    # Sortie JSON avec profondeur suffisante
    Write-Output ($result | ConvertTo-Json -Depth 10 -Compress)
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}