<#
 ==============================================================================
  session.ps1 - moteur générique de lancement de jeu

  Ce fichier n'a pas vocation à être édité : toute la configuration se fait
  dans config.ini, à la racine. Il est appelé par les raccourcis du Bureau que
  setup.ps1 a créés.

    -Game <nom>   nom d'une entrée de la section [Games] de config.ini
    -Restore      relance ce qui a été fermé au dernier passage
    -Test         déroule le cycle complet avec un faux jeu
    -Config       chemin d'un config.ini alternatif
    -AsModule     ne fait rien : charge seulement les fonctions, pour que
                  setup.ps1 (et les tests) réutilisent la lecture de config et
                  la détection des jeux sans les redéfinir

  Codes de sortie : 0 = ok, 1 = annulé par l'utilisateur, 2 = erreur.
 ==============================================================================
#>
[CmdletBinding()]
param(
    [string]$Game,
    [switch]$Restore,
    [switch]$Test,
    [string]$Config,
    [switch]$AsModule
)

$ErrorActionPreference = 'Stop'

# Les scripts vivent dans scripts\, la configuration et l'etat a la racine du
# dossier : l'utilisateur n'a sous les yeux que ce qui le concerne.
$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:Root      = Split-Path -Parent $script:ScriptDir

if (-not $Config) { $Config = Join-Path $script:Root 'config.ini' }

# config.ini est le fichier de l'utilisateur et n'est pas versionne : au premier
# lancement il n'existe pas, on le cree a partir du modele livre.
$script:ConfigTemplate = Join-Path (Split-Path -Parent $Config) `
                                   ([System.IO.Path]::GetFileNameWithoutExtension($Config) + '.exemple.ini')

# Tout l'etat entre deux parties dans un seul fichier, a cote des scripts
# plutot que sous %LOCALAPPDATA% : le dossier reste autonome et deplacable d'un
# bloc. Un seul fichier, donc une seule ligne de .gitignore.
$script:StateFile = Join-Path $script:Root 'state.json'

# Affichage commun a tout le projet. Le fichier est en UTF-8 AVEC BOM, sinon
# PowerShell 5.1 le lirait comme de l'ANSI et abimerait les accents.
. (Join-Path $script:ScriptDir 'ui.ps1')
Initialize-Console


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
#  Etat (state.json)
# ==============================================================================
#
#  Deux clefs, de durees de vie differentes :
#    games    ou se trouve chaque jeu, pour ne pas refouiller les disques
#    session  ce qui a ete ferme avant la partie, pour pouvoir le relancer
#
#  Un fichier absent ou abime n'est jamais une erreur : on repart d'un etat
#  vide, quitte a redetecter. Rien la-dedans ne merite d'interrompre une partie.

function Get-State {
    if (-not (Test-Path -LiteralPath $script:StateFile)) { return @{} }
    try {
        $state = @{}
        ((Read-TextFile $script:StateFile) | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $state[$_.Name] = $_.Value }
        return $state
    } catch {
        return @{}
    }
}

# Lire-modifier-reecrire : ecrire une clef ne doit pas effacer l'autre.
function Set-State {
    param([string]$Key, $Value)

    $state = Get-State
    $state[$Key] = $Value
    ($state | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $script:StateFile -Encoding UTF8
}

# ==============================================================================
#  Services
# ==============================================================================
#
#  Arreter ou demarrer un service demande les droits administrateur. On n'eleve
#  surtout pas tout le script : le jeu serait lance en administrateur lui aussi,
#  ce que les anticheats et les DRM voient d'un mauvais oeil, et ses sauvegardes
#  finiraient avec des droits qui genent ensuite. On eleve donc une seule
#  commande, le temps de traiter tous les services d'un coup -- un seul UAC,
#  pas un par service, et aucun si rien n'est a faire.

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Renvoie les services dont l'etat a REELLEMENT change. On verifie apres coup
# plutot que de croire un code de retour : que l'on soit passe par l'elevation
# ou non, la seule verite est l'etat du service.
function Set-ServiceState {
    param(
        [ValidateSet('Stop', 'Start')][string]$Action,
        [string[]]$Names,
        [bool]$Elevate = $true
    )

    $before = if ($Action -eq 'Stop') { 'Running' } else { 'Stopped' }
    $todo = @()
    foreach ($name in $Names) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        # Un service absent n'est pas une erreur : la config livree est generique
        if ($svc -and $svc.Status -eq $before) { $todo += $name }
    }
    if ($todo.Count -eq 0) { return @() }

    if (Test-Admin) {
        foreach ($name in $todo) {
            try {
                if ($Action -eq 'Stop') { Stop-Service -Name $name -Force -ErrorAction Stop }
                else                    { Start-Service -Name $name -ErrorAction Stop }
            } catch { }
        }
    } elseif ($Elevate) {
        # Les noms de service ne contiennent ni espace ni apostrophe : la liste
        # peut etre reinjectee telle quelle dans la commande elevee.
        $list    = ($todo | ForEach-Object { "'$_'" }) -join ','
        $verb    = if ($Action -eq 'Stop') { 'Stop-Service -Force' } else { 'Start-Service' }
        $command = "foreach (`$s in @($list)) { $verb -Name `$s -ErrorAction SilentlyContinue }"

        # L'UAC surgit sans crier gare : on dit d'ou il vient, sinon la fenetre
        # bleue arrive sans explication et on ne sait pas s'il faut accepter.
        $what = if ($Action -eq 'Stop') { 'arrêter' } else { 'redémarrer' }
        Write-Host "    Windows va demander une autorisation pour $what les services." -ForegroundColor DarkGray
        Write-Host '    Refuser ne bloque rien : le reste continue sans eux.' -ForegroundColor DarkGray

        try {
            $null = Start-Process powershell -Verb RunAs -WindowStyle Hidden -Wait -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $command
            )
        } catch {
            # UAC refuse : on continue sans les services, la partie compte plus
        }
    }

    $changed = @()
    foreach ($name in $todo) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne $before) { $changed += $name }
    }
    return $changed
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

    Start-Process -FilePath $steam -ArgumentList '-shutdown'
    $null = Wait-ProcessExit 'steam.exe' 15
    return @{ Path = $steam; State = 'Ok'; Detail = 'fermé (-shutdown)' }
}

# Les applications Electron -- Discord, VS Code, Spotify... -- ecrivent leurs
# journaux sur la console dont elles heritent. Relancees directement depuis
# notre fenetre, elles la noient sous des milliers de lignes juste apres la
# restauration. "cmd /c start" les detache, exactement comme le ferait un
# double-clic depuis l'Explorateur : elles n'ont plus de console ou ecrire.
function Start-Detached {
    param([string]$Path, [string]$Arguments, [switch]$Minimized)

    # Le "" apres start est le titre de fenetre, obligatoire des que le chemin
    # est entre guillemets -- sinon cmd prend le chemin pour un titre.
    $cmdArgs = @('/c', 'start', '""')

    # /min pour ce qui tournait sans fenetre : l'application revient discrete,
    # comme elle etait. Certaines l'ignorent et s'ouvrent quand meme -- c'est
    # une indication donnee au shell, pas une garantie.
    if ($Minimized) { $cmdArgs += '/min' }

    $cmdArgs += "`"$Path`""
    if ($Arguments) { $cmdArgs += $Arguments }

    Start-Process -FilePath 'cmd.exe' -ArgumentList $cmdArgs -WindowStyle Hidden
}

# Vrai seulement si l'application a une fenetre REELLEMENT affichee. Reduite
# dans la barre des taches, dans la zone de notification ou prechargee par
# Windows : dans les trois cas l'utilisateur ne la voyait pas, c'est de
# l'arriere-plan et elle doit y retourner.
#
# MainWindowHandle ne suffit pas ici : il reste non nul pour une fenetre
# reduite. C'est ce qui faisait revenir EA Desktop en grand.
function Test-HasWindow {
    param([string]$Name)

    try { Initialize-WindowApi } catch { return $false }

    $pids = @(Get-TargetProcess $Name | ForEach-Object { $_.Id })
    if ($pids.Count -eq 0) { return $false }

    try   { return ([GsoWindow]::FindWindows([int[]]$pids, $true).Count -gt 0) }
    catch { return $false }
}

# Certaines applications ignorent le /min du shell et s'ouvrent en grand quand
# meme -- EA Desktop en particulier, qui restaure sa propre geometrie. On les
# reduit alors nous-memes, en demandant a Windows de minimiser leur fenetre des
# qu'elle apparait.
#
#  MainWindowHandle ne suffit pas : les applications Electron -- EA Desktop,
#  Discord -- le laissent a zero alors que leur fenetre est bien affichee,
#  parce qu'elle appartient a un processus enfant. On enumere donc toutes les
#  fenetres de premier niveau du systeme et on garde celles dont le processus
#  proprietaire porte le bon identifiant.
function Initialize-WindowApi {
    if ('GsoWindow' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class GsoWindow {
    private delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] private static extern int  GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public  static extern bool ShowWindow(IntPtr h, int nCmdShow);

    // Fenetres visibles et titrees appartenant a l'un des PID. Sans titre,
    // c'est une fenetre technique : elle ne compte pas.
    //
    // openOnly : ne garder que celles reellement affichees. Une fenetre reduite
    // reste "visible" pour Windows alors que l'utilisateur ne la voit pas --
    // c'est de l'arriere-plan, et confondre les deux fait revenir en grand une
    // application qui etait sagement dans la barre des taches.
    public static List<IntPtr> FindWindows(int[] pids, bool openOnly) {
        List<IntPtr> found = new List<IntPtr>();
        EnumWindows(delegate(IntPtr h, IntPtr p) {
            if (!IsWindowVisible(h) || GetWindowTextLength(h) == 0) return true;
            if (openOnly && IsIconic(h)) return true;
            uint owner;
            GetWindowThreadProcessId(h, out owner);
            foreach (int pid in pids) {
                if (owner == (uint)pid) { found.Add(h); break; }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
'@
}

# Attend que l'application ouvre sa fenetre, puis la reduit. Appelee juste
# apres l'avoir relancee : chacune est traitee pendant qu'on s'occupe d'elle,
# et la ligne affichee decrit alors un travail termine.
#
# Sort des que c'est fait, ou au bout du delai si la fenetre n'apparait jamais
# -- l'application avait peut-etre simplement choisi de rester dans la zone de
# notification, ce qui est le resultat voulu de toute facon.
# Reduit les fenetres de $Names, en une seule attente pour tout le monde.
# Renvoie les noms qui n'ont montre aucune fenetre -- la plupart des
# applications de fond n'en ouvrent jamais, et c'est tres bien ainsi.
#
# Une attente par application couterait le delai complet pour chacune, alors
# qu'elles demarrent toutes en parallele : d'ou la passe unique.
function Hide-AppWindow {
    param([string[]]$Names, [double]$Seconds = 6)

    if (-not $Names -or $Names.Count -eq 0) { return @() }
    try { Initialize-WindowApi } catch { return @() }

    $pending  = @($Names)
    $deadline = (Get-Date).AddSeconds($Seconds)

    while ((Get-Date) -lt $deadline -and $pending.Count -gt 0) {
        Start-Sleep -Milliseconds 300

        foreach ($name in @($pending)) {
            $pids = @(Get-TargetProcess $name | ForEach-Object { $_.Id })
            if ($pids.Count -eq 0) { continue }

            try   { $windows = [GsoWindow]::FindWindows([int[]]$pids, $false) }
            catch { continue }
            if ($windows.Count -eq 0) { continue }

            # 6 = SW_MINIMIZE
            foreach ($h in $windows) { $null = [GsoWindow]::ShowWindow($h, 6) }
            $pending = @($pending | Where-Object { $_ -ne $name })
        }
    }
    return $pending
}

# Dernier recours quand le processus refuse de livrer son chemin -- cas d'une
# application lancee en administrateur, comme PowerToys : ni .Path ni WMI ne
# repondent. Le menu Demarrer contient un raccourci vers a peu pres tout ce qui
# est installe, et le registre garde les dossiers d'installation.
#
# L'index du menu Demarrer est construit une seule fois, et seulement si on en
# a besoin : le parcours recursif coute quelques centaines de millisecondes.
function Find-AppPath {
    param([string]$Name)

    if ($null -eq $script:StartMenuIndex) {
        $script:StartMenuIndex = @{}
        $shell = New-Object -ComObject WScript.Shell
        foreach ($base in @("$env:APPDATA\Microsoft\Windows\Start Menu",
                            "$env:ProgramData\Microsoft\Windows\Start Menu")) {
            foreach ($lnk in (Get-ChildItem -LiteralPath $base -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue)) {
                try {
                    $target = $shell.CreateShortcut($lnk.FullName).TargetPath
                    if (-not $target) { continue }
                    $leaf = Split-Path -Leaf $target
                    # Le premier raccourci trouve gagne : les suivants sont
                    # souvent des variantes (mode sans echec, desinstalleur...)
                    if (-not $script:StartMenuIndex.ContainsKey($leaf)) {
                        $script:StartMenuIndex[$leaf] = $target
                    }
                } catch { }
            }
        }
    }

    $found = $script:StartMenuIndex[$Name]
    if ($found -and (Test-Path -LiteralPath $found)) { return $found }

    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($app in (Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue)) {
        if (-not $app.InstallLocation) { continue }

        # Certains installeurs stockent le chemin entre guillemets, ce qui suffit
        # a faire echouer Join-Path ("A drive with the name '`"C' does not
        # exist"). Le try attrape le reste : rien ici ne merite d'interrompre
        # une preparation de partie.
        try {
            $folder = $app.InstallLocation.Trim().Trim('"')
            if (-not $folder) { continue }
            $candidate = Join-Path $folder $Name
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        } catch { }
    }
    return $null
}

# Le chemin sert a la restauration : c'est lui qui evite d'avoir a saisir les
# chemins d'installation dans config.ini. .Path echoue sur les processus plus
# privilegies que nous, d'ou le repli sur WMI puis sur Find-AppPath.
function Get-ProcessPath {
    param($Process, [string]$Name)

    try { if ($Process.Path) { return $Process.Path } } catch { }
    try {
        $ci = Get-CimInstance Win32_Process -Filter "ProcessId = $($Process.Id)" -ErrorAction SilentlyContinue
        if ($ci -and $ci.ExecutablePath) { return $ci.ExecutablePath }
    } catch { }

    if ($Name) { return Find-AppPath $Name }
    return $null
}

function Wait-ProcessExit {
    param([string]$Name, [int]$Seconds)

    for ($i = 0; $i -lt $Seconds; $i++) {
        if ((Get-TargetProcess $Name).Count -eq 0) { return $true }
        Start-Sleep -Seconds 1
    }
    return ((Get-TargetProcess $Name).Count -eq 0)
}

# Attend la fin de la partie : le processus du jeu disparaît, on rend la main.
# Sondage à la seconde.
function Wait-GameExit {
    param([string]$Name)

    while ((Get-TargetProcess $Name).Count -gt 0) { Start-Sleep -Seconds 1 }
}

function Wait-ProcessStart {
    param([string]$Name, [int]$Seconds)

    for ($i = 0; $i -lt $Seconds; $i++) {
        if ((Get-TargetProcess $Name).Count -gt 0) { return $true }
        Start-Sleep -Seconds 1
    }
    return ((Get-TargetProcess $Name).Count -gt 0)
}

# Fermeture propre : WM_CLOSE, on laisse le temps de sauvegarder, on ne force
# que si l'application ne repond pas.
function Stop-AppGracefully {
    param([string]$Name, [int]$Timeout)

    $procs = Get-TargetProcess $Name
    if ($procs.Count -eq 0) { return $null }

    $path = Get-ProcessPath $procs[0] $Name

    # Sans chemin, pas de retour possible : on n'y touche pas.
    if (-not $path) {
        return @{ Path = $null; State = 'Warn'; Detail = 'chemin illisible, laissé ouvert' }
    }

    # Aucune fenetre de premier niveau : le WM_CLOSE n'a personne a qui parler,
    # attendre le delai complet ne ferait que le perdre. Cas courant des
    # applications qui vivent dans la zone de notification (EA Desktop) ou en
    # tache de fond (msedge en prechargement).
    if (@($procs | Where-Object { $_.MainWindowHandle -ne 0 }).Count -eq 0) {
        foreach ($p in $procs) { try { $p.Kill() } catch { } }
        return @{ Path = $path; State = 'Ok'; Detail = 'fermé (aucune fenêtre)' }
    }

    foreach ($p in $procs) { try { $null = $p.CloseMainWindow() } catch { } }

    if (Wait-ProcessExit $Name $Timeout) {
        return @{ Path = $path; State = 'Ok'; Detail = 'fermé' }
    }

    foreach ($p in (Get-TargetProcess $Name)) { try { $p.Kill() } catch { } }
    return @{ Path = $path; State = 'Warn'; Detail = 'ne répondait pas, fermeture forcée' }
}

# Aucune fenetre de premier niveau : le WM_CLOSE n'aurait personne a qui parler,
# attendre ne servirait a rien. Rien a sauvegarder non plus.
function Stop-AppForced {
    param([string]$Name)

    $procs = Get-TargetProcess $Name
    if ($procs.Count -eq 0) { return $null }

    $path = Get-ProcessPath $procs[0] $Name

    # Sans chemin, on ne saurait pas la relancer : on ne la ferme pas. Mieux
    # vaut une application de trop pendant la partie qu'une application perdue
    # jusqu'au prochain redemarrage. Cas typique : un processus lance en
    # administrateur, qui ne livre son chemin ni par .Path ni par WMI.
    if (-not $path) {
        return @{ Path = $null; State = 'Warn'; Detail = 'chemin illisible, laissé ouvert' }
    }

    foreach ($p in $procs) { try { $p.Kill() } catch { } }
    return @{ Path = $path; State = 'Ok'; Detail = 'fermé' }
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
            # Game Pass : les jeux vont dans XboxGames, sous un sous-dossier
            # Content -- d'ou la profondeur de recherche un cran plus grande.
            "${r}XboxGames",
            "${r}Games",
            "${r}Jeux"
        )
    }
    foreach ($base in $roots) {
        foreach ($folder in $entry.Folders) {
            $exe = Find-Executable (Join-Path $base $folder) $entry.Exe 3
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
            Write-Failure "le chemin indiqué dans config.ini pour $Name n'existe pas :"
            Write-Hint $Declared
            Write-Hint 'Corrigez la ligne, ou remplacez le chemin par : auto'
        }
        return $null
    }

    $state = Get-State
    $cache = @{}
    if ($state['games']) {
        $state['games'].PSObject.Properties | ForEach-Object { $cache[$_.Name] = $_.Value }
    }
    if ($cache[$Name] -and (Test-Path -LiteralPath $cache[$Name])) { return $cache[$Name] }

    if (-not $Quiet) { Write-Host "    recherche de $Name sur le disque..." -ForegroundColor DarkGray }
    $exe = Find-Game $Name
    if (-not $exe) {
        if (-not $Quiet) {
            Write-Failure "impossible de trouver $Name automatiquement."
            Write-Hint 'Ouvrez config.ini et remplacez  auto  par le chemin complet'
        Write-Hint "de l'exécutable du jeu, sur la ligne  $Name ="
        }
        return $null
    }

    $cache[$Name] = $exe
    Set-State 'games' $cache
    return $exe
}

# ==============================================================================
#  Session : ce qui a ete ferme, pour pouvoir le relancer ensuite
# ==============================================================================

# Chaque lancement repart de zero : la session decrit ce qui a ete ferme
# cette fois-ci, rien d'autre.
function Save-SessionState {
    param($Apps, $Services)

    Set-State 'session' ([pscustomobject]@{
        Date     = (Get-Date).ToString('s')
        Apps     = @($Apps)
        Services = @($Services)
    })
}

# ==============================================================================
#  Mode restauration
# ==============================================================================

function Invoke-Restore {
    param($Ini)

    $session = (Get-State)['session']
    if (-not $session) {
        Write-Host ''
        Write-Host 'Rien à restaurer : aucun lancement de jeu enregistré.' -ForegroundColor Yellow
        return 0
    }

    Write-Step 'Redémarrage des services...'
    $services = @($session.Services)

    $started = @(Set-ServiceState -Action Start -Names $services `
                                  -Elevate (Get-IniBool $Ini 'Options' 'ElevateForServices' $true))

    Start-StatusList $services
    for ($i = 0; $i -lt $services.Count; $i++) {
        $name = $services[$i]
        $svc  = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $svc)                     { Update-StatusItem $i 'Info' 'service introuvable' }
        elseif ($started -contains $name)  { Update-StatusItem $i 'Ok'   'démarré' }
        elseif ($svc.Status -eq 'Running') { Update-StatusItem $i 'Info' 'déjà démarré' }
        else                               { Update-StatusItem $i 'Fail' 'échec (autorisation refusée ?)' }
    }
    Complete-StatusList
    if ($services.Count -eq 0) { Write-Host '    (aucun)' -ForegroundColor DarkGray }

    Write-Step 'Redémarrage des applications...'
    $apps = @($session.Apps)

    # Celles a remettre en arriere-plan. Toutes traitees en une fois apres la
    # boucle : les applications demarrent en parallele de toute facon, et une
    # attente par application couterait le delai autant de fois qu'il y en a.
    $pending = @()

    Start-StatusList @($apps | ForEach-Object { $_.Process })
    for ($i = 0; $i -lt $apps.Count; $i++) {
        $app = $apps[$i]

        if ((Get-TargetProcess $app.Process).Count -gt 0) {
            Update-StatusItem $i 'Info' 'déjà lancé'
            continue
        }
        if (-not $app.Path -or -not (Test-Path -LiteralPath $app.Path)) {
            Update-StatusItem $i 'Warn' 'chemin introuvable'
            continue
        }
        try {
            # Ce qui tournait sans fenetre revient reduit : on remet la machine
            # comme elle etait, pas huit fenetres en travers du bureau.
            if ($app.Background) {
                Start-Detached $app.Path (Get-IniValue $Ini 'Arguments' $app.Process) -Minimized
                $pending += $app.Process
                Update-StatusItem $i 'Ok' 'démarré (réduit)'
            } else {
                Start-Detached $app.Path (Get-IniValue $Ini 'Arguments' $app.Process)
                Update-StatusItem $i 'Ok' 'démarré'
            }
        } catch {
            Update-StatusItem $i 'Fail' 'échec au démarrage'
        }
    }
    Complete-StatusList
    if ($apps.Count -eq 0) { Write-Host '    (aucune)' -ForegroundColor DarkGray }

    # Une seule attente pour tout le monde. Silencieux : la ligne "demarre
    # (reduit)" a deja ete affichee pour chacune.
    $null = Hide-AppWindow $pending 6

    Write-Host ''
    Write-Host 'Terminé.' -ForegroundColor Green
    return 0
}

# ==============================================================================
#  Mode lancement
# ==============================================================================

function Invoke-Launch {
    param($Ini, [string]$Name, [switch]$Test)

    if ($Test) {
        # Le cycle complet, mais avec un faux jeu : tout est reellement ferme
        # et restaure, seul le jeu est remplace par une fenetre qui attend.
        # Rien a declarer dans [Games], c'est un mode a part.
        $exe = Join-Path $script:ScriptDir 'fake-game.bat'
        if (-not (Test-Path -LiteralPath $exe)) {
            Write-Failure 'fake-game.bat est introuvable a cote de session.ps1.'
            return 2
        }
        $title = 'Test (faux jeu)'
        # Un .bat s'execute dans cmd.exe : c'est ce processus qu'on surveille
        $gameProcess = 'cmd.exe'
        # Aucun launcher epargne : le test ferme tout, c'est bien l'interet
        $launcher = $null
    } else {
        $declared = Get-IniValue $Ini 'Games' $Name
        if ($null -eq $declared) {
            Write-Failure "le jeu `"$Name`" n'est pas déclaré dans config.ini."
            Write-Hint "Ajoutez une ligne   $Name = auto   sous [Games]."
            return 2
        }

        $exe = Resolve-GamePath $Name $declared
        if (-not $exe) { return 2 }
        $gameProcess = Split-Path -Leaf $exe

        # Nom lisible du jeu, pour l'affichage. A defaut, la cle de [Games] fait
        # l'affaire : c'est deja un nom, juste plus court.
        $title = Get-IniValue $Ini "Game.$Name" 'Title' $Name

        # Le launcher dont le jeu a besoin pour demarrer. Il est le seul a
        # echapper aux fermetures : le fermer serait le meilleur moyen
        # d'empecher le lancement. Declare a la main, faute d'indice fiable
        # dans le chemin du jeu.
        $launcher = Get-IniValue $Ini "Game.$Name" 'Launcher'
    }

    $closeTimeout = Get-IniInt $Ini 'Options' 'CloseTimeout' 8
    $startTimeout = Get-IniInt $Ini 'Options' 'StartTimeout' 30

    # Applications a ne pas relancer QUAND elles tournaient en arriere-plan,
    # c'est-a-dire sans fenetre. Avec une fenetre ouverte, elles sont rouvertes
    # normalement : l'utilisateur s'en servait vraiment.
    $noReopen = @(Get-IniList $Ini 'NoReopen')

    # Vrai si l'application doit etre oubliee : declaree dans [NoReopen] et sans
    # fenetre au moment ou on la ferme. A appeler AVANT de la fermer.
    function Test-SkipReopen {
        param([string]$App)

        if ($noReopen -notcontains $App) { return $false }
        return (-not (Test-HasWindow $App))
    }

    # Retient aussi comment l'application tournait, pour la remettre pareil :
    # une application reduite dans la zone de notification doit y revenir, pas
    # s'ouvrir en grand au milieu du bureau.
    function New-ClosedApp {
        param([string]$App, [string]$Path, [bool]$HadWindow)

        return [pscustomobject]@{
            Process    = $App
            Path       = $Path
            Background = (-not $HadWindow)
        }
    }

    # ---- 1. Verifications ---------------------------------------------------
    Write-Step '[1/6] Vérifications...'

    # En mode test on les passe toutes : c'est justement ce qu'on veut eprouver.
    # Liste vide = preflight.ps1 execute l'integralite de ce qu'il connait, sans
    # avoir a en tenir un double ici.
    if ($Test) {
        $checkList = @()
    } else {
        $checks = Get-IniValue $Ini "Game.$Name" 'Checks'
        if ($null -eq $checks) { $checks = Get-IniValue $Ini 'Options' 'Checks' '' }
        $checkList = @($checks -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    $ok = $true
    $preflight = Join-Path $script:ScriptDir 'preflight.ps1'
    if (-not $Test -and $checkList.Count -eq 0) {
        Write-Host '    (aucune vérification configurée)' -ForegroundColor DarkGray
    } elseif (-not (Test-Path -LiteralPath $preflight)) {
        Write-Host '    [  ?  ] vérifications ignorées : preflight.ps1 introuvable' -ForegroundColor DarkGray
    } else {
        . $preflight -AsModule
        $ok = Invoke-Preflight -Checks $checkList
    }

    # Une seule question, quel que soit le nombre de problemes, et ici plutot
    # qu'au lancement : a ce stade rien n'a ete ferme, annuler ne coute rien.
    if (-not $ok) {
        Write-Host ''
        $answer = Read-Host '    Vérification(s) en échec. Continuer quand même ? [o/N]'
        if ($answer -notmatch '^\s*[oyOY]') {
            Write-Host ''
            Write-Host "Lancement annulé. Aucune application n'a été fermée." -ForegroundColor Yellow
            return 1
        }
    }

    # A partir d'ici on touche a la machine : la session repart de zero. Une
    # session precedente encore presente serait perimee, et "Tout rouvrir"
    # relancerait des applications d'une partie d'avant.
    #
    # Efface ici et pas plus haut : tant que la question du preflight n'a pas
    # eu de reponse, annuler ne doit rien couter.
    Set-State 'session' $null

    $closedApps     = @()
    $stoppedServices = @()

    # ---- 2. Services --------------------------------------------------------
    Write-Step '[2/6] Arrêt des services...'
    $serviceList = @(Get-IniList $Ini 'Services')
    # L'indexation Windows est un gros consommateur d'E/S disque, cause classique
    # de micro-freezes en pleine partie.
    if (Get-IniBool $Ini 'Options' 'StopSearchIndexing' $true) { $serviceList += 'WSearch' }

    # Ce qui tournait avant, pour distinguer plus bas ce qui a resiste
    $running = @($serviceList | Where-Object {
        $svc = Get-Service -Name $_ -ErrorAction SilentlyContinue
        $svc -and $svc.Status -eq 'Running'
    })

    $stoppedServices = @(Set-ServiceState -Action Stop -Names $serviceList `
                                          -Elevate (Get-IniBool $Ini 'Options' 'ElevateForServices' $true))

    Start-StatusList $running
    for ($i = 0; $i -lt $running.Count; $i++) {
        if ($stoppedServices -contains $running[$i]) { Update-StatusItem $i 'Ok' 'arrêté' }
        else { Update-StatusItem $i 'Fail' 'échec (autorisation refusée ?)' }
    }
    Complete-StatusList
    if ($running.Count -eq 0) { Write-Host '    (aucun service à arrêter)' -ForegroundColor DarkGray }
    # ---- 3. Fermeture propre ------------------------------------------------
    Write-Step '[3/6] Fermeture propre des applications...'

    # Les launchers sont une section a part dans config.ini -- leur sort depend
    # du jeu lance -- mais ils se ferment exactement comme les autres.
    $toClose = @(Get-IniList $Ini 'CloseGracefully') + @(Get-IniList $Ini 'Launchers')

    # Seules celles qui tournent vraiment entrent dans la liste : afficher les
    # quinze entrees de config.ini quand trois sont lancees noierait le reste.
    $toClose = @($toClose | Where-Object {
        (Get-TargetProcess $_).Count -gt 0 -or ($launcher -and $_ -eq $launcher)
    })

    Start-StatusList $toClose
    for ($i = 0; $i -lt $toClose.Count; $i++) {
        $app = $toClose[$i]

        if ($launcher -and $app -eq $launcher) {
            Update-StatusItem $i 'Info' "conservé — launcher de $title"
            continue
        }

        # A evaluer avant de fermer : apres, il n'y a plus de fenetre a observer
        $hadWindow = Test-HasWindow $app
        $skip      = Test-SkipReopen $app

        $r = if ($app -eq 'steam.exe') { Stop-Steam } else { Stop-AppGracefully $app $closeTimeout }
        if (-not $r) { Update-StatusItem $i 'Info' 'pas en cours'; continue }

        Update-StatusItem $i $r.State $r.Detail
        if ($r.Path -and -not $skip) { $closedApps += New-ClosedApp $app $r.Path $hadWindow }
    }
    Complete-StatusList

    # ---- 4. Fermeture forcee ------------------------------------------------
    Write-Step '[4/6] Fermeture des utilitaires et serveurs...'

    $forced = @(Get-IniList $Ini 'CloseForced' | Where-Object {
        (Get-TargetProcess $_).Count -gt 0 -or ($launcher -and $_ -eq $launcher)
    })

    Start-StatusList $forced
    for ($i = 0; $i -lt $forced.Count; $i++) {
        $app = $forced[$i]

        if ($launcher -and $app -eq $launcher) {
            Update-StatusItem $i 'Info' "conservé — launcher de $title"
            continue
        }

        $hadWindow = Test-HasWindow $app
        $skip      = Test-SkipReopen $app
        $r         = Stop-AppForced $app
        if (-not $r) { Update-StatusItem $i 'Info' 'pas en cours'; continue }

        Update-StatusItem $i $r.State $r.Detail
        if ($r.Path -and -not $skip) { $closedApps += New-ClosedApp $app $r.Path $hadWindow }
    }
    Complete-StatusList

    # ---- 5. Taches de fond --------------------------------------------------
    Write-Step '[5/6] Mise en pause des tâches de fond...'

    # La Xbox Game Bar enregistre en continu pendant le jeu. Ces processus se
    # relancent seuls a la demande : rien a restaurer, rien a enregistrer.
    if (Get-IniBool $Ini 'Options' 'StopXboxGameBar' $true) {
        foreach ($p in @('GameBar.exe', 'GameBarFTServer.exe', 'GameBarPresenceWriter.exe', 'XboxGameBarWidgets.exe')) {
            $null = Stop-AppForced $p
        }
        Write-Status 'Xbox Game Bar' 'Ok' 'arrêtée'
    }

    Save-SessionState $closedApps $stoppedServices

    # ---- 6. Lancement -------------------------------------------------------
    Write-Step "[6/6] Lancement de $title..."
    try {
        # Detache lui aussi : un jeu bavard noierait la console qui doit rester
        # lisible pendant toute la partie.
        Start-Detached $exe
    } catch {
        Write-Failure 'impossible de lancer le jeu :'
        Write-Hint $exe
        return 2
    }

    # Le titre du jeu, pas le mot « démarrage » : la ligne se lit alors comme
    # toutes les autres, un nom à gauche et son état à droite.
    Write-StatusStart $title
    if (Wait-ProcessStart $gameProcess $startTimeout) {
        Write-StatusEnd 'Ok' 'lancé, bon match !'

        # ---- Apres la partie : restauration automatique ---------------------
        # Les 6 etapes numerotees sont celles de la preparation ; ce qui suit
        # n'en est pas une, on attend simplement la fin de la partie.
        if (-not (Get-IniBool $Ini 'Options' 'AutoRestore' $true)) { return 0 }

        Write-Host ''
        Write-Host 'Partie en cours.' -ForegroundColor DarkGray
        Write-Host 'Cette fenêtre se réveillera à la fermeture du jeu pour tout remettre' -ForegroundColor DarkGray
        Write-Host 'en place. La fermer maintenant n''annule rien : le raccourci' -ForegroundColor DarkGray
        Write-Host '"Tout rouvrir" fait exactement la même chose, à la demande.' -ForegroundColor DarkGray

        Wait-GameExit $gameProcess

        Write-Host ''
        Write-Host "$title s'est fermé, restauration..." -ForegroundColor Green
        return (Invoke-Restore $Ini)
    }

    Write-Host ''
    Write-Host ''
    # Le nom du processus reste en indice : c'est lui qu'on a guette, et le
    # savoir aide a comprendre pourquoi rien n'a ete vu.
    Write-Host "ATTENTION : $title n'a pas démarré après $startTimeout s." -ForegroundColor Yellow
    Write-Hint "(processus attendu : $gameProcess)"
    Write-Hint 'Le launcher a peut-être besoin d''une connexion ou d''une mise à jour.'
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
            Write-Host "    ($(Split-Path -Leaf $Config) créé à partir de $(Split-Path -Leaf $script:ConfigTemplate))" -ForegroundColor DarkGray
        } else {
            Write-Failure 'config.ini introuvable, et aucun modèle pour le créer :'
            Write-Hint $Config
            Wait-AnyKey
            exit 2
        }
    }
    $ini = Read-IniFile $Config

    if ($Restore) {
        $exitCode = Invoke-Restore $ini
    } elseif ($Test) {
        $exitCode = Invoke-Launch $ini '' -Test
    } elseif ($Game) {
        $exitCode = Invoke-Launch $ini $Game
    } else {
        Write-Failure 'aucun jeu indiqué. Utilisez un raccourci "Lancer ..." du Bureau.'
        $exitCode = 2
    }
} catch {
    Write-Failure $_.Exception.Message
    $exitCode = 2
}

# Quand tout s'est bien passe, la fenetre disparait : on vient de jouer, on n'a
# rien a lire. Elle attend une touche dans trois cas seulement :
#
#   - une erreur, sinon le message defilerait sans que personne le voie ;
#   - le mode test, dont le resultat est justement ce qu'on est venu regarder ;
#   - KeepWindowOpen = true, pour qui veut relire le detail a chaque fois.
$keepOpen = $false
if ($ini) { $keepOpen = Get-IniBool $ini 'Options' 'KeepWindowOpen' $false }

if ($exitCode -eq 2 -or $Test -or $keepOpen) { Wait-AnyKey }
exit $exitCode
