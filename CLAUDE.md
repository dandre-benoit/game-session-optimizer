# game-session-optimizer

Outil Windows qui prépare le PC avant une partie (ferme les applications de
fond, arrête des services, vérifie le matériel), lance le jeu, puis remet tout
en place après. Destiné à être partagé : il doit fonctionner sur une machine
inconnue sans rien installer.

## Architecture

| Fichier | Rôle |
|---|---|
| `setup.bat` | seul `.bat` du projet, double-cliquable : lance `setup.ps1` |
| `setup.ps1` | crée les raccourcis du Bureau, un par jeu de `[Games]` plus « Tout rouvrir ». Idempotent : relancer est la façon normale de prendre en compte un ajout de jeu |
| `session.ps1` | le moteur : il porte la session de jeu entière, de la préparation à la remise en état |
| `preflight.ps1` | vérifications matérielles, chargées par le moteur via `. preflight.ps1 -AsModule` puis `Invoke-Preflight -Checks` |
| `config.ini` | la configuration lue par le moteur, **jamais versionnée** |
| `config.exemple.ini` | le modèle livré, dont `config.ini` est créé au premier lancement |
| `README.md` | documentation utilisateur (destinée à des amis non techniciens) |

Cible : **PowerShell 5.1**, présent d'origine sur Windows 10/11. Aucune
dépendance externe, aucune installation. `setup.bat` et les raccourcis du
Bureau invoquent PowerShell avec `-NoProfile -ExecutionPolicy Bypass`.

## Les raccourcis du Bureau

Un `.lnk` créé via `WScript.Shell` COM, dont la cible est `powershell.exe` et
les arguments `-File <session.ps1> -Game <NOM>`. Trois conséquences à garder :

- **L'icône est celle de l'exécutable du jeu** (`"$exe,0"`), ce qui suppose de
  résoudre le jeu au moment du setup. **Un jeu introuvable n'a pas de
  raccourci** : un `.lnk` qui échoue au double-clic est pire que pas de `.lnk`
  du tout. Ce n'est pas une erreur pour autant — le setup continue, liste les
  jeux sautés à la fin et dit quoi faire. D'où le `-Quiet` de
  `Resolve-GamePath`, dont les messages ne conviennent qu'au contexte d'un
  lancement.
- **Le ménage se fait par les arguments** : un `.lnk` nous appartient si ses
  arguments contiennent le chemin de *notre* `session.ps1`. Deux copies du
  dossier ne se marchent donc pas dessus, et un raccourci personnel de
  l'utilisateur n'est jamais supprimé. Ne pas remplacer ce test par une
  correspondance sur le nom du fichier.
- **`ShortcutFolder`** choisit l'emplacement, le Bureau par défaut. Le ménage
  balaie la cible et le Bureau — ce dernier parce que c'est de là qu'on vient
  quand l'option est renseignée pour la première fois. Passer d'un dossier
  personnalisé à un autre laisse les anciens sur place : c'est assumé, mémoriser
  l'emplacement précédent dans `state/` a été essayé et retiré, la complexité ne
  valait pas ce cas de figure.
- **Les chemins sont absolus** : déplacer le dossier casse les raccourcis, il
  faut relancer `setup.bat`. C'est documenté dans le README.

`session.ps1 -AsModule` charge les fonctions sans rien exécuter — c'est ce qui
permet à `setup.ps1` de réutiliser la lecture de config et la détection des jeux
au lieu de les redéfinir, et c'est aussi le point d'entrée des tests.

## Conventions

**Nommage des fichiers** — minuscules, tirets, pas d'espaces (`session.ps1`,
`play-bf6.bat`, `config.exemple.ini`). Seules exceptions, conventionnelles :
`README.md` et `CLAUDE.md`.

**Langue** — tous les identifiants en anglais : fonctions, paramètres,
variables, mais aussi les sections et clés de `config.ini` (`[CloseGracefully]`,
`StartTimeout`), puisqu'elles sont consommées par le code. Les commentaires et
la documentation sont en français.

**Encodage** — les `.ps1` sont en **ASCII pur**, y compris dans les
commentaires. Deux raisons cumulées : PowerShell 5.1 lit un `.ps1` sans BOM
comme de l'ANSI, et la console héritée du `.bat` tourne en codepage OEM. Les
accents y sortiraient cassés. Les `.ini` et les `.md`, eux, sont en UTF-8 avec
accents — ils sont lus par un humain, dans le Bloc-notes ou sur la page du
dépôt, jamais affichés dans la console.

**Sortie console** — sans accents, pour la même raison.

## Points de conception à préserver

**Aucun chemin d'installation dans la config.** Au moment de fermer un
processus, le moteur relève son chemin réel (`Process.Path`, repli sur WMI pour
les processus plus privilégiés) et l'enregistre. `restore-all` relance
exactement ça. C'est ce qui rend le même `config.ini` utilisable sur n'importe
quelle machine — ne jamais réintroduire de chemin en dur.

**État dans `state.json`** — un seul fichier à la racine, deux clefs de durées
de vie différentes : `games` (où se trouve chaque jeu) et `session` (ce qui a
été fermé avant la partie). Le dossier du projet reste autonome et déplaçable
d'un bloc, sans rien écrire ailleurs sur la machine.

`Set-State` fait un lire-modifier-réécrire : écrire une clef ne doit jamais
effacer l'autre. `Get-State` renvoie un dictionnaire vide si le fichier manque
ou est abîmé — on redétecte, ce qui est toujours préférable à interrompre une
partie.

Une version antérieure utilisait un dossier `state/` avec un fichier par clef,
plus un `.gitkeep` et la subtilité `state/*` puis `!state/.gitkeep` dans cet
ordre. Un fichier unique fait le même travail avec une ligne de `.gitignore`.

Rien de volatil ne doit atterrir ailleurs que là, et rien de volatil ne doit
être versionné.

**La question avant la casse** — si une vérification échoue, on demande avant
d'avoir fermé quoi que ce soit. Annuler ne doit jamais rien coûter.

**Le launcher du jeu se déclare, il ne se devine pas.** `[Game.<nom>]
Launcher = Battle.net.exe` désigne la seule plateforme épargnée par les
fermetures. Deux approches ont été essayées puis rejetées : une liste
d'exclusions par jeu (`KeepRunning`, une double négation pour dire un fait
simple), puis la déduction depuis le chemin d'installation. Cette dernière ne
marche que par accident — `steamapps` et `Epic Games` nomment la plateforme,
mais Battle.net installe dans un dossier au nom du jeu, et un `Call of Duty`
acheté sur Steam serait attribué à Battle.net. Le chemin nomme le jeu, pas la
plateforme : il n'y a rien à en déduire. Une ligne explicite par jeu coûte
moins cher qu'un lancement qui échoue chez un ami.

Corollaire : `steam.exe` est une entrée de `[CloseGracefully]` comme les
autres, et non plus une option `StopSteam`. Le seul cas particulier restant est
`Stop-Steam`, qui utilise le `-shutdown` officiel au lieu d'un `WM_CLOSE`.

**Le cycle complet dans un seul processus** — avec `AutoRestore` (défaut), la
console reste ouverte pendant la partie, `Wait-GameExit` attend la fermeture du
jeu, puis `Invoke-Restore` s'exécute. C'est ce qui justifie le nom du fichier :
il porte la session entière, pas seulement le lancement.

Deux garde-fous indispensables ici. D'abord le **délai de grâce**
(`AutoRestoreDelay`) : un launcher relance parfois le processus du jeu — mise à
jour, retour au menu — et sans ce délai tout rouvrirait en pleine partie. Après
la disparition du processus, on observe et on repart en attente s'il revient.
Ensuite, l'automatisme ne doit jamais être le **seul** chemin : si l'utilisateur
ferme la console, `restore-all.bat` doit rester capable de tout remettre en
place. La session est écrite sur disque *avant* le lancement du jeu, jamais
après.

Le sondage d'attente est volontairement lent (5 s) : la boucle peut tourner des
heures.

**Vérifications adaptatives** — une vérification inapplicable (pas de carte
NVIDIA) est signalée `?` et ne fait pas échouer le lancement. Seul un vrai
défaut compte comme un échec.

**Une entrée absente n'est pas une erreur** — une application listée mais non
installée, un service inexistant : on passe en silence. La config livrée est
volontairement généreuse.

## Configuration

`config.ini` appartient à l'utilisateur et **n'est pas versionné**. Le dépôt
livre `config.exemple.ini` ; au premier lancement, le moteur copie l'un sur
l'autre si `config.ini` est absent. Sans cela, un `git clone` suivi d'un
double-clic échouerait faute de configuration.

Un mécanisme de fusion `config.ini` + `config.local.ini` a existé puis été
retiré : deux fichiers à tenir pour un outil que l'utilisateur édite de toute
façon à la main, ça ne payait pas sa complexité. Ne pas le réintroduire sans
raison nouvelle.

Le parseur garde les lignes brutes par section, ce qui permet de traiter avec
le même code une liste (`chrome.exe`) et un réglage (`StartTimeout = 60`) :
`Get-IniKey` donne l'identité d'une ligne — la partie à gauche du `=` s'il y en
a un, la ligne entière sinon. Il est insensible à la casse et tolère
`oui/yes/1/on` en plus de `true/false`, mais tout ce qui est livré et documenté
utilise `true/false`.

## Pièges connus

**Batch** — pas de bloc `if ( ... )` dans les `.bat` : si le dossier est placé
dans un chemin contenant des parenthèses (`Program Files (x86)`), la
substitution de `%~dp0` ferme le bloc trop tôt, erreur de syntaxe, et la fenêtre
se referme d'un coup. Utiliser `goto`.

**Encodage des `.ini`** — `Read-TextFile` décode en UTF-8 si le contenu est de
l'UTF-8 valide, en ANSI sinon. Un ami peut enregistrer depuis le Bloc-notes dans
l'un ou l'autre ; un chemin accentué doit rester lisible dans les deux cas.

**`-File` et les tableaux** — `powershell -File script.ps1 -Checks A,B,C` livre
`"A,B,C"` comme une seule chaîne. `Invoke-Preflight` redécoupe à l'entrée.

## Tester sans casser la machine

Ne **jamais** exécuter le cycle complet pour vérifier une modification : il
fermerait les applications en cours. Approche utilisée :

1. Vérifier la syntaxe avec `[System.Management.Automation.Language.Parser]::ParseFile`.
2. Extraire les fonctions du moteur (tout ce qui précède la section « Point
   d'entrée ») dans un fichier temporaire, le dot-sourcer, et tester les
   fonctions une à une.
3. Pour les tests sur processus réels, copier un exécutable inoffensif sous un
   nom dédié (`Copy-Item $env:WINDIR\System32\PING.EXE FauxJeu.exe`) plutôt que
   d'agir sur un vrai processus. Ne jamais cibler `powershell.exe` : ce serait
   la session de test elle-même.
4. Sauvegarder puis restaurer `last-session.json` autour d'un test qui l'écrit.

`Wait-KeyPress` bloque sur une vraie console même avec l'entrée redirigée : les
branches d'erreur qui s'y terminent ne sont pas testables automatiquement.
