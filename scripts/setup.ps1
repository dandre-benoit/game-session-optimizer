<#
 ==============================================================================
  setup.ps1 - crée les raccourcis de lancement

  Un raccourci par jeu déclaré dans [Games], un pour tout rouvrir après la
  partie, et un « Tester ma configuration » si TestShortcut vaut true.
  Un jeu introuvable est ignoré : créer un raccourci qui ne lance rien ne
  rendrait service à personne. L'icône de chaque raccourci est celle du jeu
  lui-même. Ils vont sur le Bureau, ou dans le dossier indiqué par
  ShortcutFolder.

  Relançable à volonté : les raccourcis existants sont refaits, et ceux des
  jeux retirés de config.ini disparaissent. C'est la manière normale de prendre
  en compte un ajout de jeu.

  Lancé par setup.bat, mais utilisable seul.
 ==============================================================================
#>
[CmdletBinding()]
param(
    [string]$Config
)

$ErrorActionPreference = 'Stop'

# Les scripts vivent dans scripts\, la configuration a la racine du dossier.
$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:Root      = Split-Path -Parent $script:ScriptDir

# Affichage commun. Charge avant le moteur : les premieres erreurs possibles
# surviennent justement quand celui-ci est introuvable.
. (Join-Path $script:ScriptDir 'ui.ps1')
Initialize-Console

$engine = Join-Path $script:ScriptDir 'session.ps1'

if (-not (Test-Path -LiteralPath $engine)) {
    Write-Host ''
    Write-Host 'ERREUR : session.ps1 est introuvable dans le dossier scripts.' -ForegroundColor Red
    Write-Host '         Les fichiers doivent rester ensemble dans le même dossier.' -ForegroundColor DarkGray
    Wait-AnyKey
    exit 2
}

# Le moteur porte deja la lecture de config et la detection des jeux : on les
# recharge plutot que de les redefinir ici.
. $engine -AsModule

if (-not $Config) { $Config = Join-Path $script:Root 'config.ini' }
$template = Join-Path $script:Root 'config.exemple.ini'

# Meme regle qu'au lancement d'une partie : config.ini n'est pas livre.
if (-not (Test-Path -LiteralPath $Config)) {
    if (-not (Test-Path -LiteralPath $template)) {
        Write-Host ''
        Write-Host 'ERREUR : ni config.ini ni config.exemple.ini dans ce dossier.' -ForegroundColor Red
        Wait-AnyKey
        exit 2
    }
    Copy-Item -LiteralPath $template -Destination $Config
    $configCreated = $true
}

$ini   = Read-IniFile $Config
$shell = New-Object -ComObject WScript.Shell

$desktop = [Environment]::GetFolderPath('Desktop')

# Ou deposer les raccourcis. Vide ou absent : le Bureau. Les variables
# d'environnement sont acceptees (%USERPROFILE%, %APPDATA%...), et un chemin
# relatif part du dossier du projet -- "shortcuts" y cree un sous-dossier.
$target = Get-IniValue $ini 'Options' 'ShortcutFolder' ''
if ($target) {
    $target = [Environment]::ExpandEnvironmentVariables($target).Trim('"').TrimEnd('\')
    if (-not [System.IO.Path]::IsPathRooted($target)) { $target = Join-Path $script:Root $target }
} else {
    $target = $desktop
}

if (-not (Test-Path -LiteralPath $target)) {
    try {
        $null = New-Item -ItemType Directory -Path $target -Force
    } catch {
        Write-Host ''
        Write-Host "ERREUR : impossible de créer le dossier des raccourcis :" -ForegroundColor Red
        Write-Host "         $target" -ForegroundColor DarkGray
        Write-Host '         Corrigez ShortcutFolder dans config.ini.' -ForegroundColor DarkGray
        Wait-AnyKey
        exit 2
    }
}

# ------------------------------------------------------------------------------
#  Creation des raccourcis
# ------------------------------------------------------------------------------

# Le titre vient de config.ini : rien n'empeche un utilisateur d'y mettre un
# caractere interdit dans un nom de fichier. On les retire plutot que de laisser
# la creation du .lnk echouer sur "Call of Duty 4: Modern Warfare".
function Get-SafeFileName {
    param([string]$Name)

    foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) {
        $Name = $Name.Replace([string]$c, '')
    }
    return ($Name -replace '\s+', ' ').Trim()
}

# Un raccourci lance toujours le moteur : powershell -File session.ps1 ...
# C'est ce qui permet de les reconnaitre plus bas pour faire le menage.
function New-Shortcut {
    param(
        [string]$Name,
        [string]$Arguments,
        [string]$IconPath,
        [string]$Description
    )

    $path = Join-Path $target "$(Get-SafeFileName $Name).lnk"
    $lnk  = $shell.CreateShortcut($path)

    $lnk.TargetPath       = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $lnk.Arguments        = "-NoProfile -ExecutionPolicy Bypass -File `"$engine`" $Arguments"
    $lnk.WorkingDirectory = $script:Root
    $lnk.Description      = $Description
    if ($IconPath) { $lnk.IconLocation = $IconPath }
    $lnk.Save()

    return $path
}

# Un raccourci nous appartient s'il pointe vers notre propre session.ps1.
# Deux copies du dossier a des endroits differents ne se marchent donc pas
# dessus, et un raccourci personnel de l'utilisateur n'est jamais touche.
#
# On balaie le dossier cible mais aussi le Bureau : si ShortcutFolder vient
# d'etre renseigne, les raccourcis du Bureau seraient sinon abandonnes la.
function Remove-OwnShortcuts {
    param([string[]]$Folders)

    $removed = 0
    foreach ($folder in ($Folders | Where-Object { $_ } | Select-Object -Unique)) {
        foreach ($file in (Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -File -ErrorAction SilentlyContinue)) {
            try {
                $lnk = $shell.CreateShortcut($file.FullName)
                if ($lnk.Arguments -like "*$engine*") {
                    Remove-Item -LiteralPath $file.FullName -Force
                    $removed++
                }
            } catch { }
        }
    }
    return $removed
}

# ------------------------------------------------------------------------------

if ($configCreated) {
    Write-Host ''
    Write-Host 'Première utilisation : config.ini vient d''être créé à partir du modèle.' -ForegroundColor Cyan
    Write-Host 'Les raccourcis ci-dessous correspondent aux jeux qu''il contient. Pour en' -ForegroundColor DarkGray
    Write-Host 'ajouter, ouvrez config.ini avec le Bloc-notes puis relancez setup.bat.' -ForegroundColor DarkGray
}

Write-Step 'Création des raccourcis dans :'
Write-Host "    $target" -ForegroundColor Cyan
Write-Host ''

$old = Remove-OwnShortcuts @($target, $desktop)
if ($old -gt 0) { Write-Host "    ($old ancien(s) raccourci(s) remplacé(s))" -ForegroundColor DarkGray }

$games   = @(Get-IniList $ini 'Games')
$created = 0
$skipped = @()

if ($games.Count -eq 0) {
    Write-Host '    aucun jeu déclaré dans [Games] : rien à créer.' -ForegroundColor Yellow
}

# Les raccourcis fixes, connus d'avance : ils rejoignent la même liste que les
# jeux pour que tout s'affiche d'un seul bloc.
$fixes = @()
if (Get-IniBool $ini 'Options' 'TestShortcut' $false) { $fixes += 'Tester ma configuration' }
$fixes += 'Tout rouvrir'

# Nom lisible de chaque jeu, à défaut la clé de [Games] : c'est lui qui nomme
# le raccourci, « Lancer Battlefield 6 » plutôt que « Lancer BF6 ».
$titles = @($games | ForEach-Object { Get-IniValue $ini "Game.$_" 'Title' $_ })

# Toute la liste s'affiche en attente, puis chaque ligne se résout
Start-StatusList (@($titles) + $fixes)

for ($i = 0; $i -lt $games.Count; $i++) {
    $game  = $games[$i]
    $title = $titles[$i]

    # Il faut savoir ou est le jeu, pour son icone mais surtout pour ne pas
    # creer un raccourci qui ne lancerait rien.
    $exe = $null
    try { $exe = Resolve-GamePath $game (Get-IniValue $ini 'Games' $game) -Quiet } catch { }

    if (-not $exe) {
        Update-StatusItem $i 'Warn' 'jeu introuvable, pas de raccourci'
        $skipped += $game
        continue
    }

    $null = New-Shortcut -Name "Lancer $title" `
                         -Arguments "-Game $game" `
                         -IconPath "$exe,0" `
                         -Description "Prépare le PC et lance $title"
    Update-StatusItem $i 'Ok' 'raccourci créé'
    $created++
}

# Les raccourcis qui ne correspondent a aucun jeu, pour le resume final
$extras = @()
$rang   = $games.Count

# Raccourci de test : le cycle complet avec un faux jeu, pour verifier que tout
# ferme et rouvre correctement sans lancer une vraie partie. Hors defaut : ca ne
# concerne que celui qui bricole l'outil.
if ($fixes -contains 'Tester ma configuration') {
    $null = New-Shortcut -Name 'Tester ma configuration' `
                         -Arguments '-Test' `
                         -IconPath "$env:WINDIR\System32\shell32.dll,23" `
                         -Description 'Cycle complet avec un faux jeu, pour vérifier l''outil'
    Update-StatusItem $rang 'Ok' 'raccourci créé'
    $extras += 'Tester ma configuration'
    $rang++
}

# Icone de restauration : la fleche circulaire de shell32.dll. Purement
# cosmetique -- si l'index bouge d'une version de Windows a l'autre, le
# raccourci fonctionne quand meme.
$null = New-Shortcut -Name 'Tout rouvrir' `
                     -Arguments '-Restore' `
                     -IconPath "$env:WINDIR\System32\shell32.dll,238" `
                     -Description 'Remet en place ce qui a été fermé avant la partie'
Update-StatusItem $rang 'Ok' 'raccourci créé'
$extras += 'Tout rouvrir'

Complete-StatusList
Write-Host ''
Write-Host "Terminé. $created raccourci(s) de jeu, plus $($extras -join ' et ')." -ForegroundColor Green

if ($skipped.Count -gt 0) {
    Write-Host ''
    Write-Host "Sans raccourci, faute d'avoir trouvé le jeu : $($skipped -join ', ')" -ForegroundColor Yellow
    Write-Host '  - soit le jeu n''est pas installé sur ce PC ;' -ForegroundColor DarkGray
    Write-Host '  - soit il l''est, mais ailleurs qu''aux endroits cherchés : dans ce cas' -ForegroundColor DarkGray
    Write-Host '    ouvrez config.ini et remplacez  auto  par le chemin complet de son' -ForegroundColor DarkGray
    Write-Host '    exécutable, sous [Games].' -ForegroundColor DarkGray
    Write-Host '  Relancez setup ensuite.' -ForegroundColor DarkGray
}

Write-Host ''
Write-Host 'Relancez setup quand vous ajoutez un jeu dans config.ini.' -ForegroundColor DarkGray
Write-Host ''
Wait-AnyKey
exit 0
