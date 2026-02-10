# Guide d'installation DSC - Configuration automatisée Windows

## Installation

### 1. Récupération du code source

Clonez ou téléchargez le projet :

```powershell
git clone https://github.com/GuyLescalier/WaC
cd WaC
```

---

## Configuration des modules

---

## Installation des ressources personnalisées

### 6. Déploiement des ressources DSC custom

```powershell
# Débloquer le script d'installation
Unblock-File .\Install-MyDscResources.ps1

# Exécuter l'installation
.\Install-MyDscResources.ps1
```

---

## Utilisation et tests

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
