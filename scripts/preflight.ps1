<#
 ==============================================================================
  preflight.ps1 - vérifications matérielles avant lancement

  Appelé par session.ps1, qui lui passe la liste des vérifications utiles au
  jeu concerné (section [Game.<nom>] de config.ini). Les vérifications se
  déclarent par leur nom :

      TPM, SecureBoot, ResizableBAR, NvidiaDriver, DiskSpace

  Une vérification qui ne s'applique pas à la machine (pas de carte NVIDIA,
  par exemple) est signalée « ? » et ne fait pas échouer le lancement : seul ce
  qui est réellement en défaut compte comme un échec.

  Utilisable seul (double-clic ou -File) : il exécute alors toutes les
  vérifications et renvoie 0 si tout va bien, 1 sinon.
 ==============================================================================
#>
param(
    [string[]]$Checks = @(),
    [switch]$AsModule
)

# Affichage partagé avec le reste du projet : mêmes symboles, mêmes couleurs,
# même alignement pour une vérification matérielle que pour une application
# fermée. Le fichier est en UTF-8 AVEC BOM, sinon PowerShell 5.1 le lirait
# comme de l'ANSI et abîmerait les accents.
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'ui.ps1')
Initialize-Console

# $Ok à $null : la vérification ne s'applique pas à cette machine. Ce n'est pas
# un échec — seul un vrai défaut doit empêcher de jouer.
# $Ok à $null : la vérification ne s'applique pas à cette machine. Ce n'est pas
# un échec — seul un vrai défaut doit empêcher de jouer.
#
# La ligne existe déjà, réservée par Start-StatusList : on ne fait que la
# remplir, à la place qu'elle occupe.
function Write-Check {
    param([string]$Label, [nullable[bool]]$Ok, [string]$Detail)

    if     ($null -eq $Ok) { $state = 'Info' }
    elseif ($Ok)           { $state = 'Ok' }
    else                   { $state = 'Fail'; $script:AllOk = $false }

    Update-StatusItem $script:CheckIndex $state $Detail
    $script:CheckIndex++
}

# ------------------------------------------------------------------------------
#  TPM 2.0
#  tpmtool plutôt que Get-CimInstance Win32_Tpm : ce dernier exige l'élévation,
#  ce qui déclencherait un UAC à chaque lancement du jeu.
# ------------------------------------------------------------------------------
function Test-Tpm {
    try {
        $out = & tpmtool getdeviceinformation 2>&1 | Out-String
    } catch {
        Write-Check 'TPM 2.0' $null 'tpmtool indisponible'
        return
    }

    $version = if ($out -match '-TPM Version:\s*([\d.]+)') { $Matches[1] } else { $null }
    $present = $out -match '-TPM Present:\s*True'
    $ready   = $out -match '-Is Initialized:\s*True'

    if (-not $present -or -not $version) {
        Write-Check 'TPM 2.0' $false 'aucun TPM détecté (à activer dans le BIOS)'
        return
    }
    if ($version -notlike '2.*') {
        Write-Check 'TPM 2.0' $false "version $version - l'anticheat exige la 2.0"
        return
    }
    if (-not $ready) {
        Write-Check 'TPM 2.0' $false 'présent mais non initialisé'
        return
    }

    $vulnerable = if ($out -match '-TPM Has Vulnerable Firmware:\s*True') { ', firmware vulnérable' } else { '' }
    Write-Check 'TPM 2.0' $true "actif et initialisé$vulnerable"
}

# ------------------------------------------------------------------------------
#  Secure Boot - exigé aussi par les anticheats au niveau noyau.
#  Le registre se lit sans élévation, contrairement à Confirm-SecureBootUEFI.
# ------------------------------------------------------------------------------
function Test-SecureBoot {
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State'
    $value = (Get-ItemProperty -Path $key -Name UEFISecureBootEnabled -ErrorAction SilentlyContinue).UEFISecureBootEnabled

    if ($null -eq $value) {
        Write-Check 'Secure Boot' $false 'état introuvable (BIOS en mode Legacy/CSM ?)'
    } elseif ($value -eq 1) {
        Write-Check 'Secure Boot' $true 'activé'
    } else {
        Write-Check 'Secure Boot' $false 'désactivé (à activer dans le BIOS)'
    }
}

# ------------------------------------------------------------------------------
#  Tout ce qui vient du GPU en une fois : trois appels à nvidia-smi coûtaient
#  240 ms, deux en coûtent 100. « -q -d MEMORY » suffit pour BAR1 et va trois
#  fois plus vite que le « -q » complet.
# ------------------------------------------------------------------------------
function Get-GpuInfo {
    if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) { return $null }

    try {
        $csv = (& nvidia-smi --query-gpu=memory.total,driver_version --format=csv,noheader,nounits |
                Select-Object -First 1) -split ',\s*'
        $memory = & nvidia-smi -q -d MEMORY | Out-String
        $bar1 = if ($memory -match 'BAR1 Memory Usage[\s\S]{0,200}?Total\s*:\s*(\d+)\s*MiB') { [int]$Matches[1] } else { $null }
    } catch {
        return $null
    }

    [pscustomobject]@{
        Vram   = [int]$csv[0]
        Driver = $csv[1].Trim()
        Bar1   = $bar1
    }
}

# nvidia-smi coûte ~100 ms : on ne l'interroge qu'à la première vérification GPU
function Get-CachedGpuInfo {
    if (-not $script:GpuLoaded) {
        $script:Gpu       = Get-GpuInfo
        $script:GpuLoaded = $true
    }
    return $script:Gpu
}

# ------------------------------------------------------------------------------
#  Resizable BAR
#  Le seuil fiable est « BAR1 >= VRAM », pas une valeur fixe : sans ReBAR la
#  fenêtre BAR1 est plafonnée à 256 Mo quelle que soit la carte.
# ------------------------------------------------------------------------------
function Test-ResizableBar {
    param($Gpu)

    if ($null -eq $Gpu) {
        Write-Check 'Resizable BAR' $null 'vérification propre aux cartes NVIDIA'
        return
    }
    if ($null -eq $Gpu.Bar1) {
        Write-Check 'Resizable BAR' $null 'taille BAR1 illisible'
        return
    }

    if ($Gpu.Bar1 -ge $Gpu.Vram) {
        Write-Check 'Resizable BAR' $true "actif - BAR1 $($Gpu.Bar1) Mo / VRAM $($Gpu.Vram) Mo"
    } else {
        Write-Check 'Resizable BAR' $false "inactif - BAR1 $($Gpu.Bar1) Mo seulement (à activer dans le BIOS)"
    }
}

# ------------------------------------------------------------------------------
#  Pilote NVIDIA
#  La version Game Ready est commune à toute la gamme GeForce supportée : un
#  seul lookup suffit, sans avoir à identifier le modèle exact.
# ------------------------------------------------------------------------------
function Test-NvidiaDriver {
    param($Gpu)

    if ($null -eq $Gpu) {
        Write-Check 'Pilote NVIDIA' $null 'vérification propre aux cartes NVIDIA'
        return
    }
    $installed = $Gpu.Driver

    $url = 'https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php' +
           '?func=DriverManualLookup&psid=101&pfid=877&osID=135&languageCode=1033' +
           '&isWHQL=1&dch=1&sort1=0&numberOfResults=1'
    try {
        $latest = (Invoke-RestMethod -Uri $url -TimeoutSec 10).IDS[0].downloadInfo.Version
        # Le cast [version] échouerait si NVIDIA changeait de format ; ce serait
        # absurde de faire tomber tout le preflight pour une simple info
        $upToDate = [version]$installed -ge [version]$latest
    } catch {
        Write-Check 'Pilote NVIDIA' $null "$installed (vérification en ligne indisponible)"
        return
    }

    if ($upToDate) {
        Write-Check 'Pilote NVIDIA' $true "$installed (à jour)"
    } else {
        # Pas un échec : un pilote en retard dégrade, il n'empêche pas de jouer
        Write-Check 'Pilote NVIDIA' $null "$installed - version $latest disponible"
    }
}

# ------------------------------------------------------------------------------
#  Espace disque du lecteur système. Un disque saturé fait tomber les jeux et
#  les mises à jour de launcher de façon très peu explicite.
# ------------------------------------------------------------------------------
function Test-DiskSpace {
    $drive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
    if (-not $drive) {
        Write-Check 'Espace disque' $null 'lecteur système illisible'
        return
    }
    $freeGb = [math]::Round($drive.Free / 1GB, 1)

    if ($freeGb -lt 15) {
        Write-Check 'Espace disque' $false "$freeGb Go libres sur $env:SystemDrive (peu)"
    } else {
        Write-Check 'Espace disque' $true "$freeGb Go libres sur $env:SystemDrive"
    }
}

# ------------------------------------------------------------------------------
#  Orchestration. Renvoie $true si aucune vérification n'est en échec.
# ------------------------------------------------------------------------------
# Libellé affiché pour chaque vérification. Séparé des fonctions Test-* pour
# que la liste puisse être dressée avant de commencer le travail.
$script:CheckLabels = [ordered]@{
    'tpm'          = 'TPM 2.0'
    'tpm2'         = 'TPM 2.0'
    'secureboot'   = 'Secure Boot'
    'resizablebar' = 'Resizable BAR'
    'rebar'        = 'Resizable BAR'
    'nvidiadriver' = 'Pilote NVIDIA'
    'diskspace'    = 'Espace disque'
}

function Invoke-Preflight {
    param([string[]]$Checks = @())

    $script:AllOk     = $true
    $script:GpuLoaded = $false
    $script:Gpu       = $null

    # Appelé avec -File, PowerShell livre « A,B,C » comme une seule chaîne :
    # on redécoupe, ce qui accepte aussi bien la liste que la chaîne.
    $Checks = @($Checks | ForEach-Object { $_ -split '[,;]' } |
                ForEach-Object { $_.Trim() } | Where-Object { $_ })

    if ($Checks.Count -eq 0) {
        $Checks = @('TPM', 'SecureBoot', 'ResizableBAR', 'NvidiaDriver', 'DiskSpace')
    }

    # Toute la liste s'affiche en attente, puis chaque ligne se résout
    $labels = @($Checks | ForEach-Object {
        $connu = $script:CheckLabels[$_.ToLower()]
        if ($connu) { $connu } else { $_ }
    })
    Start-StatusList $labels
    $script:CheckIndex = 0

    foreach ($check in $Checks) {
        switch ($check.ToLower()) {
            'tpm'          { Test-Tpm }
            'tpm2'         { Test-Tpm }
            'secureboot'   { Test-SecureBoot }
            'resizablebar' { Test-ResizableBar (Get-CachedGpuInfo) }
            'rebar'        { Test-ResizableBar (Get-CachedGpuInfo) }
            'nvidiadriver' { Test-NvidiaDriver (Get-CachedGpuInfo) }
            'diskspace'    { Test-DiskSpace }
            default        { Write-Check $check $null 'vérification inconnue (voir config.ini)' }
        }
    }
    Complete-StatusList
    return $script:AllOk
}

# Exécuté seul (double-clic, ou powershell -File) : on joue les vérifications et
# on renvoie un code de sortie. Chargé par session.ps1 avec -AsModule : on se
# contente de définir les fonctions.
if (-not $AsModule) {
    exit $(if (Invoke-Preflight -Checks $Checks) { 0 } else { 1 })
}
