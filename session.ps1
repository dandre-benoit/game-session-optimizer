<#
 ==============================================================================
  session.ps1 - moteur generique de lancement de jeu

  Ce fichier n'a pas vocation a etre edite : toute la configuration se fait
  dans config.ini, a cote. Il est appele par les raccourcis du Bureau que
  setup.ps1 a crees.

    -Game <nom>   nom d'une entree de la section [Games] de config.ini
    -Restore      relance ce qui a ete ferme au dernier passage
    -Config       chemin d'un config.ini alternatif
    -AsModule     ne fait rien : charge seulement les fonctions, pour que
                  setup.ps1 (et les tests) reutilisent la lecture de config et
                  la detection des jeux sans les redefinir

  Codes de sortie : 0 = ok, 1 = annule par l'utilisateur, 2 = erreur.
 ==============================================================================
#>
[CmdletBinding()]
param(
    [string]$Game,
    [switch]$Restore,
    [string]$Config,
    [switch]$AsModule
)

$ErrorActionPreference = 'Stop'

$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Config) { $Config = Join-Path $script:Root 'config.ini' }

# config.ini est le fichier de l'utilisateur et n'est pas versionne : au premier
# lancement il n'existe pas, on le cree a partir du modele livre.
$script:ConfigTemplate = Join-Path (Split-Path -Parent $Config) `
                                   ([System.IO.Path]::GetFileNameWithoutExtension($Config) + '.exemple.ini')

# Etat entre deux parties, dans un sous-dossier du projet plutot que sous
# %LOCALAPPDATA% : le dossier reste autonome et deplacable d'un bloc. Son
# contenu est ignore par git, seul le dossier lui-meme est versionne.
$script:StateDir      = Join-Path $script:Root 'state'
$script:SessionFile   = Join-Path $script:StateDir 'last-session.json'
$script:GameCacheFile = Join-Path $script:StateDir 'detected-games.json'

# Fichier en ASCII pur, accents compris dans les commentaires : PowerShell 5.1
# lit un .ps1 sans BOM comme de l'ANSI, et la console heritee du .bat tourne en
# codepage OEM. Les deux abimeraient les accents.

# ==============================================================================
#  Affichage
# ==============================================================================

function Write-Line {
    param([string]$Text, [string]$Status = '', [string]$Color = 'Gray')
    Write-Host "    - $Text" -NoNewline
    if ($Status) { Write-Host " $Status" -ForegroundColor $Color } else { Write-Host '' }
}

function Write-Failure {
    param([string]$Text)
    Write-Host ''
    Write-Host "ERREUR : $Text" -ForegroundColor Red
}

function Write-Hint {
    param([string]$Text)
    Write-Host "         $Text" -ForegroundColor DarkGray
}

function Wait-KeyPress {
    Write-Host ''
    Write-Host 'Appuyez sur une touche pour fermer...' -ForegroundColor DarkGray
    # ReadKey n'existe pas hors console interactive : dans ce cas on ne bloque pas
    try   { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }
    catch { Start-Sleep -Seconds 5 }
}

# ==============================================================================
#  Lecture de config.ini
# ==============================================================================

# Un ami peut enregistrer le fichier en UTF-8 comme en ANSI selon son Bloc-notes.
# On decode en UTF-8 quand c'est de l'UTF-8 valide, en ANSI sinon : un chemin
# contenant un accent (C:\Users\Benoit...) reste lisible dans les deux cas.
function Read-TextFile {
    param([string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    try {
        return (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes)
    } catch {
        return [System.Text.Encoding]::Default.GetString($bytes)
    }
}

# Chaque section garde ses lignes brutes : une section peut etre une liste
# (une entree par ligne) aussi bien qu'un ensemble de cles = valeurs.
function Read-IniFile {
    param([string]$Path)

    $ini = @{}
    $section = 'General'
    $ini[$section] = New-Object System.Collections.ArrayList

    foreach ($line in ((Read-TextFile $Path) -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { continue }
        if ($t -match '^\[(.+)\]$') {
            $section = $Matches[1].Trim()
            if (-not $ini.ContainsKey($section)) { $ini[$section] = New-Object System.Collections.ArrayList }
            continue
        }
        $null = $ini[$section].Add($t)
    }
    return $ini
}

# Identifiant d'une ligne : la partie a gauche du "=" quand il y en a un, la
# ligne entiere sinon. C'est ce qui permet de traiter de la meme facon une
# section de reglages (cle = valeur) et une simple liste d'applications.
function Get-IniKey {
    param([string]$Line)
    $i = $Line.IndexOf('=')
    if ($i -ge 1) { return $Line.Substring(0, $i).Trim() }
    return $Line.Trim()
}

function Get-IniSection {
    param($Ini, [string]$Name)
    foreach ($key in $Ini.Keys) {
        # -eq entre chaines est deja insensible a la casse : [Games] et [games] marchent
        if ($key -eq $Name) { return $Ini[$key] }
    }
    return @()
}

function Get-IniValue {
    param($Ini, [string]$Section, [string]$Key, $Default = $null)

    foreach ($line in (Get-IniSection $Ini $Section)) {
        $i = $line.IndexOf('=')
        if ($i -lt 1) { continue }
        if ($line.Substring(0, $i).Trim() -eq $Key) {
            return $line.Substring($i + 1).Trim()
        }
    }
    return $Default
}

# "chrome.exe" et "chrome.exe =" sont equivalents dans une section de liste.
function Get-IniList {
    param($Ini, [string]$Section)

    $result = @()
    foreach ($line in (Get-IniSection $Ini $Section)) {
        $item = Get-IniKey $line
        if ($item) { $result += $item }
    }
    return $result
}

# Tolerant en lecture (oui / yes / 1 / on fonctionnent aussi), mais tout ce qui
# est livre et documente utilise true / false.
function Get-IniBool {
    param($Ini, [string]$Section, [string]$Key, [bool]$Default)

    $v = Get-IniValue $Ini $Section $Key
    if ($null -eq $v -or $v -eq '') { return $Default }
    return @('true', 'oui', 'yes', '1', 'on') -contains $v.ToLower()
}

function Get-IniInt {
    param($Ini, [string]$Section, [string]$Key, [int]$Default)

    $v = Get-IniValue $Ini $Section $Key
    $n = 0
    if ([int]::TryParse($v, [ref]$n) -and $n -ge 0) { return $n }
    return $Default
}

# ==============================================================================
#  Processus
# ==============================================================================

function Get-TargetProcess {
    param([string]$Name)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    return @(Get-Process -Name $base -ErrorAction SilentlyContinue)
}

# Steam est le seul launcher a offrir un arret officiel en ligne de commande.
# Les autres se ferment comme une application ordinaire.
function Stop-Steam {
    $steam = Get-SteamPath
    if (-not $steam) { return $null }

    Write-Host '    - steam.exe ' -NoNewline
    Start-Process -FilePath $steam -ArgumentList '-shutdown'
    $null = Wait-ProcessExit 'steam.exe' 15
    Write-Host ' ok' -ForegroundColor Green
    return $steam
}

# Le chemin sert a la restauration : c'est lui qui evite d'avoir a saisir les
# chemins d'installation dans config.ini. .Path echoue sur les processus plus
# privilegies que nous, d'ou le repli sur WMI.
function Get-ProcessPath {
    param($Process)

    try { if ($Process.Path) { return $Process.Path } } catch { }
    try {
        $ci = Get-CimInstance Win32_Process -Filter "ProcessId = $($Process.Id)" -ErrorAction SilentlyContinue
        if ($ci -and $ci.ExecutablePath) { return $ci.ExecutablePath }
    } catch { }
    return $null
}

function Wait-ProcessExit {
    param([string]$Name, [int]$Seconds)

    for ($i = 0; $i -lt $Seconds; $i++) {
        if ((Get-TargetProcess $Name).Count -eq 0) { return $true }
        Start-Sleep -Seconds 1
        Write-Host '.' -NoNewline
    }
    return ((Get-TargetProcess $Name).Count -eq 0)
}

# Attend la fin de la partie. Un launcher relance parfois le processus du jeu
# (mise a jour, passage par le menu, changement de mode) : apres sa disparition
# on observe un delai de grace et on verifie qu'il ne revient pas avant de
# conclure que la partie est finie.
function Wait-GameExit {
    param([string]$Name, [int]$GraceSeconds = 30)

    while ($true) {
        # Sondage lent : la partie dure des heures, inutile d'y passer du CPU
        while ((Get-TargetProcess $Name).Count -gt 0) { Start-Sleep -Seconds 5 }

        $cameBack = $false
        for ($i = 0; $i -lt $GraceSeconds; $i++) {
            Start-Sleep -Seconds 1
            if ((Get-TargetProcess $Name).Count -gt 0) { $cameBack = $true; break }
        }
        if (-not $cameBack) { return }
    }
}

function Wait-ProcessStart {
    param([string]$Name, [int]$Seconds)

    for ($i = 0; $i -lt $Seconds; $i++) {
        if ((Get-TargetProcess $Name).Count -gt 0) { return $true }
        Start-Sleep -Seconds 1
        Write-Host '.' -NoNewline
    }
    return ((Get-TargetProcess $Name).Count -gt 0)
}

# Fermeture propre : WM_CLOSE, on laisse le temps de sauvegarder, on ne force
# que si l'application ne repond pas.
function Stop-AppGracefully {
    param([string]$Name, [int]$Timeout)

    $procs = Get-TargetProcess $Name
    if ($procs.Count -eq 0) { return $null }

    $path = Get-ProcessPath $procs[0]
    Write-Host "    - $Name " -NoNewline
    foreach ($p in $procs) { try { $null = $p.CloseMainWindow() } catch { } }

    if (Wait-ProcessExit $Name $Timeout) {
        Write-Host ' ok' -ForegroundColor Green
    } else {
        Write-Host ' ne repond pas, fermeture forcee' -ForegroundColor Yellow
        foreach ($p in (Get-TargetProcess $Name)) { try { $p.Kill() } catch { } }
    }
    return $path
}

# Aucune fenetre de premier niveau : le WM_CLOSE n'aurait personne a qui parler,
# attendre ne servirait a rien. Rien a sauvegarder non plus.
function Stop-AppForced {
    param([string]$Name, [switch]$Quiet)

    $procs = Get-TargetProcess $Name
    if ($procs.Count -eq 0) { return $null }

    $path = Get-ProcessPath $procs[0]
    if (-not $Quiet) { Write-Line $Name '(force)' 'DarkGray' }
    foreach ($p in $procs) { try { $p.Kill() } catch { } }
    return $path
}

# ==============================================================================
#  Detection automatique des jeux
# ==============================================================================

# Sert uniquement quand config.ini dit "auto" ; un chemin explicite court-circuite
# tout ce qui suit.
$script:GameCatalog = @{
    'BF6' = @{
        Exe     = @('bf6.exe')
        Folders = @('Battlefield 6')
        Names   = @('Battlefield 6')
    }
    'MW4' = @{
        Exe     = @('cod.exe', 'mw4.exe', 'ModernWarfare4.exe')
        Folders = @('Call of Duty', 'Call of Duty Modern Warfare IV', 'Modern Warfare IV')
        Names   = @('Call of Duty')
    }
}

function Find-Executable {
    param([string]$Folder, [string[]]$Names, [int]$Depth = 3)

    if (-not $Folder -or -not (Test-Path -LiteralPath $Folder)) { return $null }
    foreach ($name in $Names) {
        $found = Get-ChildItem -LiteralPath $Folder -Filter $name -Recurse -Depth $Depth -File -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

function Get-SteamPath {
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $p = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($p.SteamExe -and (Test-Path -LiteralPath $p.SteamExe)) { return $p.SteamExe }
        if ($p.InstallPath) {
            $exe = Join-Path $p.InstallPath 'steam.exe'
            if (Test-Path -LiteralPath $exe) { return $exe }
        }
    }
    $default = Join-Path ${env:ProgramFiles(x86)} 'Steam\steam.exe'
    if (Test-Path -LiteralPath $default) { return $default }
    return $null
}

# libraryfolders.vdf liste les bibliotheques installees sur d'autres disques.
function Get-SteamLibraries {
    $steam = Get-SteamPath
    if (-not $steam) { return @() }

    $root = Split-Path -Parent $steam
    $libs = @(Join-Path $root 'steamapps\common')

    $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        $content = Get-Content -LiteralPath $vdf -Raw
        foreach ($m in ([regex]'"path"\s+"([^"]+)"').Matches($content)) {
            $libs += Join-Path ($m.Groups[1].Value -replace '\\\\', '\') 'steamapps\common'
        }
    }
    return $libs
}

function Find-Game {
    param([string]$Name)

    $entry = $script:GameCatalog[$Name]
    if (-not $entry) { return $null }

    # 1. Registre : source la plus fiable des qu'un jeu a un desinstalleur
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($app in (Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue)) {
        if (-not $app.DisplayName -or -not $app.InstallLocation) { continue }
        foreach ($pattern in $entry.Names) {
            if ($app.DisplayName -like "*$pattern*") {
                $exe = Find-Executable $app.InstallLocation $entry.Exe 3
                if ($exe) { return $exe }
            }
        }
    }

    # 2. Bibliotheques Steam, y compris celles des disques secondaires
    foreach ($lib in (Get-SteamLibraries)) {
        foreach ($folder in $entry.Folders) {
            $exe = Find-Executable (Join-Path $lib $folder) $entry.Exe 3
            if ($exe) { return $exe }
        }
    }

    # 3. Emplacements habituels des launchers, sur chaque disque fixe
    $roots = @()
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        if (-not $drive.Root -or $drive.Root -notmatch '^[A-Za-z]:\\$') { continue }
        $r = $drive.Root
        $roots += @(
            "${r}Program Files\EA Games",
            "${r}Program Files (x86)\EA Games",
            "${r}Program Files\Epic Games",
            "${r}Program Files (x86)\Epic Games",
            "${r}Program Files\Battle.net",
            "${r}Program Files (x86)\Call of Duty",
            "${r}Games",
            "${r}Jeux"
        )
    }
    foreach ($base in $roots) {
        foreach ($folder in $entry.Folders) {
            $exe = Find-Executable (Join-Path $base $folder) $entry.Exe 2
            if ($exe) { return $exe }
        }
    }
    return $null
}

# La detection coute quelques secondes : on ne la refait qu'une fois par jeu.
#
# -Quiet : setup.ps1 resout les jeux uniquement pour recuperer leur icone. Un
# jeu absent y est normal (on cree le raccourci quand meme), alors qu'au
# lancement c'est un echec a expliquer. Les messages ne conviennent donc qu'a
# l'un des deux appelants.
function Resolve-GamePath {
    param([string]$Name, [string]$Declared, [switch]$Quiet)

    if ($Declared -and $Declared -ne 'auto') {
        if (Test-Path -LiteralPath $Declared) { return $Declared }
        if (-not $Quiet) {
            Write-Failure "le chemin indique dans config.ini pour $Name n'existe pas :"
            Write-Hint $Declared
            Write-Hint 'Corrigez la ligne, ou remplacez le chemin par : auto'
        }
        return $null
    }

    $cache = @{}
    if (Test-Path -LiteralPath $script:GameCacheFile) {
        try {
            (Get-Content -LiteralPath $script:GameCacheFile -Raw | ConvertFrom-Json).PSObject.Properties |
                ForEach-Object { $cache[$_.Name] = $_.Value }
        } catch { }
    }
    if ($cache[$Name] -and (Test-Path -LiteralPath $cache[$Name])) { return $cache[$Name] }

    if (-not $Quiet) { Write-Host "    recherche de $Name sur le disque..." -ForegroundColor DarkGray }
    $exe = Find-Game $Name
    if (-not $exe) {
        if (-not $Quiet) {
            Write-Failure "impossible de trouver $Name automatiquement."
            Write-Hint 'Ouvrez config.ini et remplacez  auto  par le chemin complet'
            Write-Hint "de l executable du jeu, sur la ligne  $Name ="
        }
        return $null
    }

    $cache[$Name] = $exe
    $null = New-Item -ItemType Directory -Path $script:StateDir -Force
    $cache | ConvertTo-Json | Set-Content -LiteralPath $script:GameCacheFile -Encoding UTF8
    return $exe
}

# ==============================================================================
#  Session : ce qui a ete ferme, pour pouvoir le relancer ensuite
# ==============================================================================

function Save-SessionState {
    param($Apps, $Services)

    $null = New-Item -ItemType Directory -Path $script:StateDir -Force
    [pscustomobject]@{
        Date     = (Get-Date).ToString('s')
        Apps     = @($Apps)
        Services = @($Services)
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:SessionFile -Encoding UTF8
}

# ==============================================================================
#  Mode restauration
# ==============================================================================

function Invoke-Restore {
    param($Ini)

    if (-not (Test-Path -LiteralPath $script:SessionFile)) {
        Write-Host ''
        Write-Host 'Rien a restaurer : aucun lancement de jeu enregistre.' -ForegroundColor Yellow
        return 0
    }
    $session = Get-Content -LiteralPath $script:SessionFile -Raw | ConvertFrom-Json

    Write-Host ''
    Write-Host 'Redemarrage des services...'
    $services = @($session.Services)
    if ($services.Count -eq 0) { Write-Host '    (aucun)' -ForegroundColor DarkGray }
    foreach ($name in $services) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-Line $name 'service introuvable, ignore' 'Yellow'
            continue
        }
        if ($svc.Status -eq 'Running') {
            Write-Line $name 'deja demarre' 'DarkGray'
            continue
        }
        try {
            Start-Service -Name $name -ErrorAction Stop
            Write-Line $name 'demarre' 'Green'
        } catch {
            Write-Line $name 'echec (droits administrateur ?)' 'Yellow'
        }
    }

    Write-Host ''
    Write-Host 'Redemarrage des applications...'
    $apps = @($session.Apps)
    if ($apps.Count -eq 0) { Write-Host '    (aucune)' -ForegroundColor DarkGray }
    foreach ($app in $apps) {
        if ((Get-TargetProcess $app.Process).Count -gt 0) {
            Write-Line $app.Process 'deja lance' 'DarkGray'
            continue
        }
        if (-not $app.Path -or -not (Test-Path -LiteralPath $app.Path)) {
            Write-Line $app.Process 'chemin introuvable, ignore' 'Yellow'
            continue
        }
        try {
            $arguments = Get-IniValue $Ini 'Arguments' $app.Process
            if ($arguments) { Start-Process -FilePath $app.Path -ArgumentList $arguments }
            else            { Start-Process -FilePath $app.Path }
            Write-Line $app.Process 'demarre' 'Green'
        } catch {
            Write-Line $app.Process 'echec au demarrage' 'Yellow'
        }
    }

    Write-Host ''
    Write-Host 'Termine.' -ForegroundColor Green
    return 0
}

# ==============================================================================
#  Mode lancement
# ==============================================================================

function Invoke-Launch {
    param($Ini, [string]$Name)

    $declared = Get-IniValue $Ini 'Games' $Name
    if ($null -eq $declared) {
        Write-Failure "le jeu `"$Name`" n'est pas declare dans config.ini."
        Write-Hint "Ajoutez une ligne   $Name = auto   sous [Games]."
        return 2
    }

    $exe = Resolve-GamePath $Name $declared
    if (-not $exe) { return 2 }
    $gameProcess = Split-Path -Leaf $exe

    $closeTimeout = Get-IniInt $Ini 'Options' 'CloseTimeout' 8
    $startTimeout = Get-IniInt $Ini 'Options' 'StartTimeout' 30

    # Nom lisible du jeu, pour l'affichage. A defaut, la cle de [Games] fait
    # l'affaire : c'est deja un nom, juste plus court.
    $title = Get-IniValue $Ini "Game.$Name" 'Title' $Name

    # Le launcher dont le jeu a besoin pour demarrer. Il est le seul a echapper
    # aux fermetures : le fermer serait le meilleur moyen d'empecher le
    # lancement. Declare a la main, faute d'indice fiable dans le chemin du jeu.
    $launcher = Get-IniValue $Ini "Game.$Name" 'Launcher'

    # ---- 1. Verifications ---------------------------------------------------
    Write-Host ''
    Write-Host '[1/6] Verifications...'

    $checks = Get-IniValue $Ini "Game.$Name" 'Checks'
    if ($null -eq $checks) { $checks = Get-IniValue $Ini 'Options' 'Checks' '' }
    $checkList = @($checks -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    $ok = $true
    $preflight = Join-Path $script:Root 'preflight.ps1'
    if ($checkList.Count -eq 0) {
        Write-Host '    (aucune verification configuree)' -ForegroundColor DarkGray
    } elseif (-not (Test-Path -LiteralPath $preflight)) {
        Write-Host '    [  ?  ] verifications ignorees : preflight.ps1 introuvable' -ForegroundColor DarkGray
    } else {
        . $preflight -AsModule
        $ok = Invoke-Preflight -Checks $checkList
    }

    # Une seule question, quel que soit le nombre de problemes, et ici plutot
    # qu'au lancement : a ce stade rien n'a ete ferme, annuler ne coute rien.
    if (-not $ok) {
        Write-Host ''
        $answer = Read-Host '    Verification(s) en echec. Continuer quand meme ? [o/N]'
        if ($answer -notmatch '^\s*[oyOY]') {
            Write-Host ''
            Write-Host "Lancement annule. Aucune application n'a ete fermee." -ForegroundColor Yellow
            return 1
        }
    }

    $closedApps     = @()
    $stoppedServices = @()

    # ---- 2. Services --------------------------------------------------------
    Write-Host ''
    Write-Host '[2/6] Arret des services...'
    $serviceList = @(Get-IniList $Ini 'Services')
    # L'indexation Windows est un gros consommateur d'E/S disque, cause classique
    # de micro-freezes en pleine partie.
    if (Get-IniBool $Ini 'Options' 'StopSearchIndexing' $true) { $serviceList += 'WSearch' }

    $anyStopped = $false
    foreach ($name in $serviceList) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $svc -or $svc.Status -ne 'Running') { continue }
        $anyStopped = $true
        try {
            Stop-Service -Name $name -Force -ErrorAction Stop
            $stoppedServices += $name
            Write-Line $name 'arrete' 'Green'
        } catch {
            Write-Line $name 'echec (droits administrateur ?)' 'Yellow'
        }
    }
    if (-not $anyStopped) { Write-Host '    (aucun service a arreter)' -ForegroundColor DarkGray }

    # ---- 3. Fermeture propre ------------------------------------------------
    Write-Host ''
    Write-Host '[3/6] Fermeture propre des applications...'
    foreach ($app in (Get-IniList $Ini 'CloseGracefully')) {
        if ($launcher -and $app -eq $launcher) {
            Write-Line $app "conserve (launcher de $title)" 'DarkGray'
            continue
        }
        if ($app -eq 'steam.exe') {
            if ((Get-TargetProcess 'steam.exe').Count -eq 0) { continue }
            $path = Stop-Steam
            if ($path) { $closedApps += [pscustomobject]@{ Process = $app; Path = $path } }
            continue
        }
        $path = Stop-AppGracefully $app $closeTimeout
        if ($path) { $closedApps += [pscustomobject]@{ Process = $app; Path = $path } }
    }

    # ---- 4. Fermeture forcee ------------------------------------------------
    Write-Host ''
    Write-Host '[4/6] Fermeture des utilitaires et serveurs...'
    foreach ($app in (Get-IniList $Ini 'CloseForced')) {
        if ($launcher -and $app -eq $launcher) {
            Write-Line $app "conserve (launcher de $title)" 'DarkGray'
            continue
        }
        $path = Stop-AppForced $app
        if ($path) { $closedApps += [pscustomobject]@{ Process = $app; Path = $path } }
    }

    # ---- 5. Taches de fond --------------------------------------------------
    Write-Host ''
    Write-Host '[5/6] Mise en pause des taches de fond...'

    # La Xbox Game Bar enregistre en continu pendant le jeu. Ces processus se
    # relancent seuls a la demande : rien a restaurer, rien a enregistrer.
    if (Get-IniBool $Ini 'Options' 'StopXboxGameBar' $true) {
        foreach ($p in @('GameBar.exe', 'GameBarFTServer.exe', 'GameBarPresenceWriter.exe', 'XboxGameBarWidgets.exe')) {
            $null = Stop-AppForced $p -Quiet
        }
        Write-Line 'Xbox Game Bar' 'arretee' 'Green'
    }

    Save-SessionState $closedApps $stoppedServices

    # ---- 6. Lancement -------------------------------------------------------
    Write-Host ''
    Write-Host "[6/6] Lancement de $title..."
    try {
        Start-Process -FilePath $exe
    } catch {
        Write-Failure 'impossible de lancer le jeu :'
        Write-Hint $exe
        return 2
    }

    Write-Host '    demarrage ' -NoNewline
    if (Wait-ProcessStart $gameProcess $startTimeout) {
        Write-Host ' ok, bon match !' -ForegroundColor Green

        # ---- Apres la partie : restauration automatique ---------------------
        # Les 6 etapes numerotees sont celles de la preparation ; ce qui suit
        # n'en est pas une, on attend simplement la fin de la partie.
        if (-not (Get-IniBool $Ini 'Options' 'AutoRestore' $true)) { return 0 }

        Write-Host ''
        Write-Host 'Partie en cours.' -ForegroundColor DarkGray
        Write-Host 'Cette fenetre se reveillera a la fermeture du jeu pour tout remettre' -ForegroundColor DarkGray
        Write-Host 'en place. La fermer maintenant n annule rien : le raccourci' -ForegroundColor DarkGray
        Write-Host '"Tout rouvrir" fait exactement la meme chose, a la demande.' -ForegroundColor DarkGray

        Wait-GameExit $gameProcess (Get-IniInt $Ini 'Options' 'AutoRestoreDelay' 30)

        Write-Host ''
        Write-Host "$gameProcess s'est ferme, restauration..." -ForegroundColor Green
        return (Invoke-Restore $Ini)
    }

    Write-Host ''
    Write-Host ''
    Write-Host "ATTENTION : $gameProcess n'est pas apparu apres $startTimeout s." -ForegroundColor Yellow
    Write-Hint 'Le launcher a peut-etre besoin d une connexion ou d une mise a jour.'
    return 2
}

# ==============================================================================
#  Point d'entree
# ==============================================================================

# Charge par setup.ps1 avec -AsModule : on se contente de definir les fonctions.
if ($AsModule) { return }

$exitCode = 2
try {
    # Premier lancement : config.ini n'est pas livre (il appartient a
    # l'utilisateur et n'est pas versionne), on le cree depuis le modele.
    if (-not (Test-Path -LiteralPath $Config)) {
        if (Test-Path -LiteralPath $script:ConfigTemplate) {
            Copy-Item -LiteralPath $script:ConfigTemplate -Destination $Config
            Write-Host ''
            Write-Host "    ($(Split-Path -Leaf $Config) cree a partir de $(Split-Path -Leaf $script:ConfigTemplate))" -ForegroundColor DarkGray
        } else {
            Write-Failure 'config.ini introuvable, et aucun modele pour le creer :'
            Write-Hint $Config
            Wait-KeyPress
            exit 2
        }
    }
    $ini = Read-IniFile $Config

    if ($Restore) {
        $exitCode = Invoke-Restore $ini
    } elseif ($Game) {
        $exitCode = Invoke-Launch $ini $Game
    } else {
        Write-Failure 'aucun jeu indique. Utilisez un raccourci "Lancer ..." du Bureau.'
        $exitCode = 2
    }
} catch {
    Write-Failure $_.Exception.Message
    $exitCode = 2
}

if ($exitCode -eq 2) { Wait-KeyPress }
exit $exitCode
