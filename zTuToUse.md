# Guide d'installation DSC - Configuration automatisée Windows

##  Installation

### 1. Installation de PowerShell 7

```powershell
winget install --id Microsoft.PowerShell --source winget
```

### 2. Installation de DSC v3

```powershell
winget install Microsoft.DSC
```

### 3. Récupération du code source

Clonez ou téléchargez le projet :

```powershell
git clone https://github.com/GuyLescalier/WaC
cd WaC
```

---

##  Configuration des modules

### 4. Configuration de l'environnement PowerShell

```powershell
# Autoriser l'exécution de scripts
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass

# Configurer PSGallery comme source fiable
Set-PSRepository PSGallery -InstallationPolicy Trusted

# Installer les modules requis
Install-Module powershell-yaml
Install-Module PSDscResources -Repository PSGallery
Install-Module PSDesiredStateConfiguration -Repository PSGallery
Install-Module Microsoft.WinGet.DSC
Install-Module Microsoft.VisualStudio.DSC
```

### 5. Emplacement des modules

Les modules peuvent être installés dans différents répertoires :

- `C:\Program Files\WindowsPowerShell\Modules\` (installation système)
- `C:\Users\<VotreNom>\Documents\WindowsPowerShell\Modules\` (installation utilisateur)
- `C:\Windows\System32\WindowsPowerShell\v1.0\Modules` (modules système comme PSDesiredStateConfiguration)

**Important :** Les modules doivent être déplacés vers le dossier PowerShell 7 :

```powershell
# Copiez manuellement les modules dans ce répertoire si nécessaire
[Environment]::GetFolderPath("MyDocuments") -> \PowerShell\Modules
```

---

##  Installation des ressources personnalisées

### 6. Déploiement des ressources DSC custom

```powershell
# Débloquer le script d'installation
Unblock-File .\Install-MyDscResources.ps1

# Exécuter l'installation (en mode utilisateur)
.\Install-MyDscResources.ps1
```

---

##  Utilisation et tests

### 7. Tester votre configuration DSC

```powershell
# Obtenir l'état actuel de la configuration
dsc config get -f .\workstation-configTestSet.yaml

# Tester si le système est dans l'état désiré
dsc config test -f .\workstation-configTestSet.yaml

# Appliquer la configuration
dsc config set -f .\workstation-configTestSet.yaml
```


**Projet source :** https://github.com/GuyLescalier/WaC