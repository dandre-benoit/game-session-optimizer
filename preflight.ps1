<#
 ==============================================================================
  preflight.ps1 - verifications materielles avant lancement

  Appele par session.ps1, qui lui passe la liste des verifications utiles au
  jeu concerne (section [Game.<nom>] de config.ini). Les verifications se
  declarent par leur nom :

      TPM, SecureBoot, ResizableBAR, NvidiaDriver, DiskSpace

  Une verification qui ne s'applique pas a la machine (pas de carte NVIDIA,
  par exemple) est signalee "?" et ne fait pas echouer le lancement : seul ce
  qui est reellement en defaut compte comme un echec.

  Utilisable seul (double-clic ou -File) : il execute alors toutes les
  verifications et renvoie 0 si tout va bien, 1 sinon.
 ==============================================================================
#>
param(
    [string[]]$Checks = @(),
    [switch]$AsModule
)

# Fichier en ASCII pur, accents compris dans les commentaires : PowerShell 5.1
# lit un .ps1 sans BOM comme de l'ANSI, et la console heritee du .bat tourne en
# codepage OEM. Les deux abimeraient les accents.

function Write-Check {
    param([string]$Label, [nullable[bool]]$Ok, [string]$Detail)

    if ($null -eq $Ok)  { $tag = '  ?  '; $color = 'DarkGray' }
    elseif ($Ok)        { $tag = ' ok  '; $color = 'Green' }
    else                { $tag = 'ECHEC'; $color = 'Red'; $script:AllOk = $false }

    Write-Host '    [' -NoNewline
    Write-Host $tag -NoNewline -ForegroundColor $color
    Write-Host "] $($Label.PadRight(16)) $Detail"
}

# ------------------------------------------------------------------------------
#  TPM 2.0
#  tpmtool plutot que Get-CimInstance Win32_Tpm : ce dernier exige l'elevation,
#  ce qui declencherait un UAC a chaque lancement du jeu.
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
        Write-Check 'TPM 2.0' $false 'aucun TPM detecte (a activer dans le BIOS)'
        return
    }
    if ($version -notlike '2.*') {
        Write-Check 'TPM 2.0' $false "version $version - l anticheat exige 2.0"
        return
    }
    if (-not $ready) {
        Write-Check 'TPM 2.0' $false 'present mais non initialise'
        return
    }

    $vulnerable = if ($out -match '-TPM Has Vulnerable Firmware:\s*True') { ', firmware vulnerable' } else { '' }
    Write-Check 'TPM 2.0' $true "actif et initialise$vulnerable"
}

# ------------------------------------------------------------------------------
#  Secure Boot - exige aussi par les anticheats au niveau noyau.
#  Le registre se lit sans elevation, contrairement a Confirm-SecureBootUEFI.
# ------------------------------------------------------------------------------
function Test-SecureBoot {
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State'
    $value = (Get-ItemProperty -Path $key -Name UEFISecureBootEnabled -ErrorAction SilentlyContinue).UEFISecureBootEnabled

    if ($null -eq $value) {
        Write-Check 'Secure Boot' $false 'etat introuvable (BIOS en mode Legacy/CSM ?)'
    } elseif ($value -eq 1) {
        Write-Check 'Secure Boot' $true 'active'
    } else {
        Write-Check 'Secure Boot' $false 'desactive (a activer dans le BIOS)'
    }
}

# ------------------------------------------------------------------------------
#  Tout ce qui vient du GPU en une fois : trois appels a nvidia-smi coutaient
#  240 ms, deux en coutent 100. "-q -d MEMORY" suffit pour BAR1 et va trois fois
#  plus vite que le "-q" complet.
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

# nvidia-smi coute ~100 ms : on ne l'interroge qu'a la premiere verification GPU
function Get-CachedGpuInfo {
    if (-not $script:GpuLoaded) {
        $script:Gpu       = Get-GpuInfo
        $script:GpuLoaded = $true
    }
    return $script:Gpu
}

# ------------------------------------------------------------------------------
#  Resizable BAR
#  Le seuil fiable est "BAR1 >= VRAM", pas une valeur fixe : sans ReBAR la
#  fenetre BAR1 est plafonnee a 256 Mo quelle que soit la carte.
# ------------------------------------------------------------------------------
function Test-ResizableBar {
    param($Gpu)

    if ($null -eq $Gpu) {
        Write-Check 'Resizable BAR' $null 'verification propre aux cartes NVIDIA'
        return
    }
    if ($null -eq $Gpu.Bar1) {
        Write-Check 'Resizable BAR' $null 'taille BAR1 illisible'
        return
    }

    if ($Gpu.Bar1 -ge $Gpu.Vram) {
        Write-Check 'Resizable BAR' $true "actif - BAR1 $($Gpu.Bar1) Mo / VRAM $($Gpu.Vram) Mo"
    } else {
        Write-Check 'Resizable BAR' $false "inactif - BAR1 $($Gpu.Bar1) Mo seulement (a activer dans le BIOS)"
    }
}

# ------------------------------------------------------------------------------
#  Pilote NVIDIA
#  La version Game Ready est commune a toute la gamme GeForce supportee : un
#  seul lookup suffit, sans avoir a identifier le modele exact.
# ------------------------------------------------------------------------------
function Test-NvidiaDriver {
    param($Gpu)

    if ($null -eq $Gpu) {
        Write-Check 'Pilote NVIDIA' $null 'verification propre aux cartes NVIDIA'
        return
    }
    $installed = $Gpu.Driver

    $url = 'https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php' +
           '?func=DriverManualLookup&psid=101&pfid=877&osID=135&languageCode=1033' +
           '&isWHQL=1&dch=1&sort1=0&numberOfResults=1'
    try {
        $latest = (Invoke-RestMethod -Uri $url -TimeoutSec 10).IDS[0].downloadInfo.Version
        # Le cast [version] echouerait si NVIDIA changeait de format ; ce serait
        # absurde de faire tomber tout le preflight pour une simple info
        $upToDate = [version]$installed -ge [version]$latest
    } catch {
        Write-Check 'Pilote NVIDIA' $null "$installed (verification en ligne indisponible)"
        return
    }

    if ($upToDate) {
        Write-Check 'Pilote NVIDIA' $true "$installed (a jour)"
    } else {
        # Pas un echec : un pilote en retard degrade, il n'empeche pas de jouer
        Write-Check 'Pilote NVIDIA' $null "$installed - version $latest disponible"
    }
}

# ------------------------------------------------------------------------------
#  Espace disque du lecteur systeme. Un disque sature fait tomber les jeux et
#  les mises a jour de launcher de facon tres peu explicite.
# ------------------------------------------------------------------------------
function Test-DiskSpace {
    $drive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
    if (-not $drive) {
        Write-Check 'Espace disque' $null 'lecteur systeme illisible'
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
#  Orchestration. Renvoie $true si aucune verification n'est en echec.
# ------------------------------------------------------------------------------
function Invoke-Preflight {
    param([string[]]$Checks = @())

    $script:AllOk     = $true
    $script:GpuLoaded = $false
    $script:Gpu       = $null

    # Appele avec -File, PowerShell livre "A,B,C" comme une seule chaine :
    # on redecoupe, ce qui accepte aussi bien la liste que la chaine.
    $Checks = @($Checks | ForEach-Object { $_ -split '[,;]' } |
                ForEach-Object { $_.Trim() } | Where-Object { $_ })

    if ($Checks.Count -eq 0) {
        $Checks = @('TPM', 'SecureBoot', 'ResizableBAR', 'NvidiaDriver', 'DiskSpace')
    }

    foreach ($check in $Checks) {
        switch ($check.ToLower()) {
            'tpm'          { Test-Tpm }
            'tpm2'         { Test-Tpm }
            'secureboot'   { Test-SecureBoot }
            'resizablebar' { Test-ResizableBar (Get-CachedGpuInfo) }
            'rebar'        { Test-ResizableBar (Get-CachedGpuInfo) }
            'nvidiadriver' { Test-NvidiaDriver (Get-CachedGpuInfo) }
            'diskspace'    { Test-DiskSpace }
            default        { Write-Check $check $null 'verification inconnue (voir config.ini)' }
        }
    }
    return $script:AllOk
}

# Execute seul (double-clic, ou powershell -File) : on joue les verifications et
# on renvoie un code de sortie. Charge par session.ps1 avec -AsModule : on se
# contente de definir les fonctions.
if (-not $AsModule) {
    exit $(if (Invoke-Preflight -Checks $Checks) { 0 } else { 1 })
}
