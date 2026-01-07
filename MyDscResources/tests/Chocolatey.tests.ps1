# Chocolatey.tests.ps1
# Tests Pester pour valider la ressource DSC Chocolatey

BeforeAll {
    # ✅ Pointer vers le sous-dossier Chocolatey DIRECTEMENT
    $resourcePath = Join-Path $PSScriptRoot "..\resources\Chocolatey"
    $resourcePath = Resolve-Path $resourcePath
    
    # Nettoyer et ajouter au PATH
    $env:PATH = $env:PATH -replace [regex]::Escape($resourcePath), ''
    $env:PATH = "$resourcePath;$env:PATH"
    
    Write-Host "`n=== Chocolatey Resource Tests ===" -ForegroundColor Cyan
    Write-Host "Resource path: $resourcePath" -ForegroundColor Yellow
    
    # Vérifier que les fichiers existent
    $manifestPath = Join-Path $resourcePath "Chocolatey.dsc.resource.json"
    $scriptPath = Join-Path $resourcePath "Chocolatey.ps1"
    
    if (-not (Test-Path $manifestPath)) {
        throw "❌ Manifest not found: $manifestPath"
    }
    
    if (-not (Test-Path $scriptPath)) {
        throw "❌ Script not found: $scriptPath"
    }
    
    Write-Host "✓ Manifest found" -ForegroundColor Green
    Write-Host "✓ Script found" -ForegroundColor Green
    
    # Vérifier la découverte DSC
    $discovered = dsc resource list 2>$null | Select-String "MyCompany.Installer/MyChocolatey"
    if (-not $discovered) {
        Write-Host "❌ Chocolatey NOT discovered by DSC!" -ForegroundColor Red
        throw "Resource discovery failed"
    }
    
    Write-Host "✓ Chocolatey discovered by DSC" -ForegroundColor Green
    Write-Host ""
}

Describe 'MyCompany.Installer/MyChocolatey Resource' {
    
    Context 'Get Operation' {
        
        It 'Returns Present if Chocolatey is installed, Absent otherwise' {
            # Act
            $jsonInput = @{ 
                name = "Chocolatey" 
            } | ConvertTo-Json -Compress
            
            $output = dsc resource get --resource MyCompany.Installer/MyChocolatey --input $jsonInput
            $result = $output | ConvertFrom-Json
            
            # Assert
            $result.actualState.ensure | Should -BeIn @('Present', 'Absent')
            $result.actualState.name | Should -Be 'Chocolatey'
        }
    }
    
    Context 'Test Operation' {
        
        It 'Returns boolean _inDesiredState property' {
            # Arrange
            $jsonInput = @{
                name = "Chocolatey"
                ensure = "Present"
            } | ConvertTo-Json -Compress
            
            # Act
            $output = dsc resource test --resource MyCompany.Installer/MyChocolatey --input $jsonInput
            $result = $output | ConvertFrom-Json
            
            # Assert
            $result.actualState | Should -Not -BeNullOrEmpty
            $result.actualState._inDesiredState | Should -BeOfType [bool]
        }
    }
    
    Context 'Set Operation' -Tag 'RequiresAdmin' {
        
        It 'Can execute Set operation for Present' {
            # Arrange
            $jsonInput = @{
                name = "Chocolatey"
                ensure = "Present"
            } | ConvertTo-Json -Compress
            
            # Act - Just verify it doesn't throw
            { dsc resource set --resource MyCompany.Installer/MyChocolatey --input $jsonInput | Out-Null } | 
                Should -Not -Throw
        }
        
        It 'Can execute Set operation for Absent' {
            # Arrange
            $jsonInput = @{
                name = "Chocolatey"
                ensure = "Absent"
            } | ConvertTo-Json -Compress
            
            # Act - Just verify it doesn't throw
            { dsc resource set --resource MyCompany.Installer/MyChocolatey --input $jsonInput | Out-Null } | 
                Should -Not -Throw
        }
    }
}

AfterAll {
    Write-Host "`nChocolatey tests completed" -ForegroundColor Green
}