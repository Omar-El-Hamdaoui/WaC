# myCho.tests.ps1
BeforeAll {
    # Ajouter le dossier de la ressource au PATH
    $resourcePath = $PSScriptRoot
    $env:PATH = "$resourcePath;$env:PATH"
    
    Write-Host "`n=== Testing MyCho DSC Resource ===" -ForegroundColor Cyan
    Write-Host "Resource path: $resourcePath" -ForegroundColor Yellow
    
    # Vérifier que les fichiers existent
    $manifestPath = Join-Path $resourcePath "myCho.dsc.resource.json"
    $scriptPath = Join-Path $resourcePath "myCho.ps1"
    
    if (-not (Test-Path $manifestPath)) {
        throw "❌ Manifest not found: $manifestPath"
    }
    
    if (-not (Test-Path $scriptPath)) {
        throw "❌ Script not found: $scriptPath"
    }
    
    Write-Host "✓ Manifest found" -ForegroundColor Green
    Write-Host "✓ Script found" -ForegroundColor Green
    
    # Vérifier que DSC découvre la ressource
    Write-Host "`nRecherche de la ressource MyCho..." -ForegroundColor Yellow
    $discovered = dsc resource list 2>&1 | Select-String "MyCompany.Installer/MyCho"
    
    if (-not $discovered) {
        Write-Host "❌ MyCho NOT discovered by DSC!" -ForegroundColor Red
        Write-Host "`nDébug info:" -ForegroundColor Yellow
        Write-Host "  PATH contains resourcePath: $($env:PATH -like "*$resourcePath*")" -ForegroundColor Gray
        Write-Host "  All discovered resources:" -ForegroundColor Gray
        dsc resource list
        throw "Resource discovery failed - DSC cannot find MyCompany.Installer/MyCho"
    }
    
    Write-Host "✓ MyCho discovered by DSC" -ForegroundColor Green
}

Describe 'MyCompany.Installer/MyCho Resource' {
    
    Context 'Get Operation' {
        
        It 'Returns Present if Chocolatey is installed, Absent otherwise' {
            # Arrange
            $jsonInput = @{ 
                name = "Chocolatey" 
            } | ConvertTo-Json -Compress
            
            # Act
            $output = dsc resource get --resource MyCompany.Installer/MyCho --input $jsonInput 2>&1
            
            # Debug output si erreur
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Error output: $output" -ForegroundColor Red
                throw "dsc resource get failed with exit code $LASTEXITCODE"
            }
            
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
            $output = dsc resource test --resource MyCompany.Installer/MyCho --input $jsonInput 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Error output: $output" -ForegroundColor Red
                throw "dsc resource test failed with exit code $LASTEXITCODE"
            }
            
            $result = $output | ConvertFrom-Json
            
            # Assert
            $result.actualState | Should -Not -BeNullOrEmpty
            # DSC transforme _inDesiredState en inDesiredState au niveau root
            $result.inDesiredState | Should -BeOfType [bool]
        }
    }
    
    Context 'Set Operation' -Tag 'RequiresAdmin' {
        
        It 'Can execute Set operation for Present' {
            # Arrange
            $jsonInput = @{
                name = "Chocolatey"
                ensure = "Present"
            } | ConvertTo-Json -Compress
            
            # Act
            $output = dsc resource set --resource MyCompany.Installer/MyCho --input $jsonInput 2>&1
            
            # Assert - ne devrait pas contenir "Resource not found"
            $output | Should -Not -Match "Resource not found"
        }
    }
}

AfterAll {
    Write-Host "`n=== Tests completed ===" -ForegroundColor Cyan
}