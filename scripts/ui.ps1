<#
 ==============================================================================
  ui.ps1 - affichage commun

  Chargé par session.ps1, setup.ps1 et preflight.ps1 via un dot-source. Toutes
  les listes du projet passent par Write-Status, pour qu'une fermeture
  d'application, un service arrêté, un raccourci créé et une vérification
  matérielle se lisent exactement de la même façon :

      ✓  chrome.exe               fermé
      ✗  wampapache64             échec (autorisation refusée ?)
      !  msedge.exe               ne répond pas, fermeture forcée
      ·  Battle.net.exe           déjà lancé

  Ce fichier ne dépend de rien : il doit pouvoir être chargé en premier, avant
  même que le moteur ne soit trouvé.
 ==============================================================================
#>

# Sans ça, la console héritée du .bat écrirait en codepage OEM et les accents
# sortiraient cassés. Le pendant obligatoire : ces fichiers sont en UTF-8 AVEC
# BOM, sinon PowerShell 5.1 les lit comme de l'ANSI.
function Initialize-Console {
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

    # Peut-on revenir réécrire une ligne déjà affichée ? Seulement devant une
    # vraie console. Dès que la sortie part dans un fichier ou un pipe, le
    # curseur n'existe plus et tout doit s'écrire une fois pour toutes.
    #
    # À déterminer AVANT d'afficher quoi que ce soit : découvrir trop tard
    # qu'on ne peut pas réécrire laisserait une liste affichée deux fois.
    $script:CanRewrite = $false
    try { $script:CanRewrite = -not [Console]::IsOutputRedirected } catch { }
}

# Largeur de la colonne des noms. Assez pour « Call of Duty 4 - Modern Warfare »,
# le plus long titre de la configuration livrée. Un nom plus long décale
# simplement le détail, sans rien casser.
$script:StatusWidth = 32

<#
  État :
    Ok    ✓ vert    l'action a réussi
    Fail  ✗ rouge   elle a échoué, et ça compte
    Warn  ! jaune   elle est passée, mais pas comme prévu
    Info  · gris    rien à faire, ou sans objet ici
#>
function Write-Status {
    param(
        [string]$Label,
        [ValidateSet('Ok', 'Fail', 'Warn', 'Info')][string]$State = 'Info',
        [string]$Detail = ''
    )

    switch ($State) {
        'Ok'   { $icon = [char]0x2713; $color = 'Green' }    # ✓
        'Fail' { $icon = [char]0x2717; $color = 'Red' }      # ✗
        'Warn' { $icon = '!';          $color = 'Yellow' }
        default{ $icon = [char]0x00B7; $color = 'DarkGray' } # ·
    }

    Write-Host '    ' -NoNewline
    Write-Host $icon -NoNewline -ForegroundColor $color
    Write-Host "  $($Label.PadRight($script:StatusWidth)) " -NoNewline
    Write-Host $Detail -ForegroundColor DarkGray
}

<#
  Variante en deux temps, pour les actions qui prennent du temps. La ligne
  s'affiche tout de suite avec un point d'attente à la place du symbole, puis
  Write-StatusEnd revient l'écrire une fois le travail fini :

      ·  chrome.exe          <- pendant l'attente, avec les points qui défilent
      ✓  chrome.exe          fermé

  Le retour en arrière se fait en repositionnant le curseur sur la ligne
  mémorisée. Si la console a défilé entre-temps, on renonce silencieusement
  plutôt que d'écrire au mauvais endroit : le détail s'affiche quand même.
#>
function Write-StatusStart {
    param([string]$Label)

    $script:StatusLabel  = $Label
    $script:StatusAnchor = $null

    # Sans vraie console — sortie redirigée dans un fichier ou un pipe — le
    # curseur ne bouge pas et il n'y a rien à réécrire. On garde alors le label
    # sous le coude et la ligne s'affichera d'un bloc à la fin.
    if (-not $script:CanRewrite) { return }
    try {
        $avant = $Host.UI.RawUI.CursorPosition
        Write-Host '    ' -NoNewline
        Write-Host ([char]0x00B7) -NoNewline -ForegroundColor DarkGray
        Write-Host "  $($Label.PadRight($script:StatusWidth)) " -NoNewline
        $script:StatusAnchor = $avant
    } catch { }
}

function Write-StatusEnd {
    param(
        [ValidateSet('Ok', 'Fail', 'Warn', 'Info')][string]$State = 'Info',
        [string]$Detail = ''
    )

    # Pas de console vivante : la ligne n'a rien affiché d'utile, on l'écrit
    # maintenant en une seule fois.
    if (-not $script:StatusAnchor) {
        Write-Status $script:StatusLabel $State $Detail
        return
    }

    switch ($State) {
        'Ok'   { $icon = [char]0x2713; $color = 'Green' }    # ✓
        'Fail' { $icon = [char]0x2717; $color = 'Red' }      # ✗
        'Warn' { $icon = '!';          $color = 'Yellow' }
        default{ $icon = [char]0x00B7; $color = 'DarkGray' } # ·
    }

    # Réécrire le symbole au début de la ligne, puis revenir où on en était
    try {
        $ici   = $Host.UI.RawUI.CursorPosition
        $cible = $script:StatusAnchor
        $cible.X = 4
        $Host.UI.RawUI.CursorPosition = $cible
        Write-Host $icon -NoNewline -ForegroundColor $color
        $Host.UI.RawUI.CursorPosition = $ici
    } catch { }

    if ($Detail) { Write-Host $Detail -ForegroundColor DarkGray } else { Write-Host '' }
}

<#
  Liste dynamique. Tout s'affiche d'un coup, en attente :

      ·  chrome.exe
      ·  msedge.exe
      ·  steam.exe

  puis chaque ligne se résout à mesure que le travail avance, sans que rien ne
  défile. On voit donc ce qui reste à faire, pas seulement ce qui est fait.

  Sans vraie console — sortie redirigée — rien ne peut être réécrit : la liste
  s'affiche alors ligne par ligne, au fil de l'eau.
#>
function Start-StatusList {
    param([string[]]$Labels)

    $script:ListLabels = @($Labels)
    $script:ListAnchor = $null
    if ($script:ListLabels.Count -eq 0 -or -not $script:CanRewrite) { return }

    try {
        foreach ($label in $script:ListLabels) { Write-Status $label 'Info' '' }

        # L'ancre se calcule en remontant depuis la position finale, et non en
        # mémorisant celle du départ : si l'écran a défilé pendant l'affichage,
        # la position du départ ne désigne plus la bonne ligne, alors que le
        # décompte depuis le bas reste juste.
        $ancre = $Host.UI.RawUI.CursorPosition
        $ancre.Y = $ancre.Y - $script:ListLabels.Count
        if ($ancre.Y -ge 0) { $script:ListAnchor = $ancre }
    } catch { }
}

function Update-StatusItem {
    param(
        [int]$Index,
        [ValidateSet('Ok', 'Fail', 'Warn', 'Info')][string]$State = 'Info',
        [string]$Detail = ''
    )

    if ($Index -lt 0 -or $Index -ge $script:ListLabels.Count) { return }
    $label = $script:ListLabels[$Index]

    # Pas de réécriture possible : on écrit la ligne à la suite
    if (-not $script:ListAnchor) {
        Write-Status $label $State $Detail
        return
    }

    try {
        $ici = $Host.UI.RawUI.CursorPosition
        $cible = $script:ListAnchor
        $cible.X = 0
        $cible.Y = $script:ListAnchor.Y + $Index
        $Host.UI.RawUI.CursorPosition = $cible

        Write-Status $label $State $Detail   # réécrit la ligne entière

        $Host.UI.RawUI.CursorPosition = $ici
    } catch { }
}

# À appeler une fois la liste traitée : replace le curseur sous la liste, pour
# que la suite s'écrive au bon endroit.
function Complete-StatusList {
    if (-not $script:ListAnchor) { return }
    try {
        $bas = $script:ListAnchor
        $bas.X = 0
        $bas.Y = $script:ListAnchor.Y + $script:ListLabels.Count
        $Host.UI.RawUI.CursorPosition = $bas
    } catch { }
    $script:ListAnchor = $null
}

# En-tête d'étape. En jaune, pour qu'on retrouve d'un coup d'œil où en est le
# déroulé quand la console est pleine de lignes de listes.
function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host $Text -ForegroundColor Yellow
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

function Wait-AnyKey {
    Write-Host ''
    Write-Host 'Appuyez sur une touche pour fermer...' -ForegroundColor DarkGray

    # Vider le tampon d'abord : pendant la partie, la console a pu recevoir des
    # frappes. Sans ce vidage, ReadKey trouverait une touche déjà en attente et
    # rendrait la main aussitôt — la fenêtre se refermerait toute seule.
    try { $Host.UI.RawUI.FlushInputBuffer() } catch { }

    # ReadKey n'existe pas hors console interactive : dans ce cas on ne bloque pas
    try   { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }
    catch { Start-Sleep -Seconds 5 }
}
