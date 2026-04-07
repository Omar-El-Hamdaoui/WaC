<#
.SYNOPSIS
    DSC v3 extension — découverte récursive des ressources WaC.
#>

$manifests = Get-ChildItem -Path $PSScriptRoot -Include '*.dsc.resource.json', '*.dsc.resource.yaml', '*.dsc.resource.yml' -Recurse -ErrorAction Ignore

foreach ($manifest in $manifests) {
    @{ manifestPath = $manifest.FullName } | ConvertTo-Json -Compress
}
