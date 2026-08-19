# game-session-optimizer

Outil Windows qui prépare le PC avant une partie (ferme les applications de
fond, arrête des services, vérifie le matériel), lance le jeu, puis remet tout
en place après. Destiné à être partagé : il doit fonctionner sur une machine
inconnue sans rien installer.

## Architecture

| Fichier | Rôle |
|---|---|
| `play-<jeu>.bat` | raccourci double-cliquable, une ligne utile : appelle le moteur avec `-Game <NOM>` |
| `restore-all.bat` | idem avec `-Restore` — filet manuel, la restauration étant automatique par défaut |
| `session.ps1` | le moteur : il porte la session de jeu entière, de la préparation à la remise en état |
| `preflight.ps1` | vérifications matérielles, chargées par le moteur via `. preflight.ps1 -AsModule` puis `Invoke-Preflight -Checks` |
| `config.ini` | configuration de base, versionnée |
| `config.local.ini` | surcharge propre à la machine, **jamais versionnée** |
| `config.local.exemple.ini` | modèle à copier |
| `readme.txt` | documentation utilisateur (destinée à des amis non techniciens) |

Cible : **PowerShell 5.1**, présent d'origine sur Windows 10/11. Aucune
dépendance externe, aucune installation. Les `.bat` invoquent le moteur avec
`-NoProfile -ExecutionPolicy Bypass`.

## Conventions

**Nommage des fichiers** — minuscules, tirets, pas d'espaces (`session.ps1`,
`play-bf6.bat`, `config.local.ini`).

**Langue** — tous les identifiants en anglais : fonctions, paramètres,
variables, mais aussi les sections et clés de `config.ini` (`[CloseGracefully]`,
`StartTimeout`), puisqu'elles sont consommées par le code. Les commentaires et
la documentation sont en français.

**Encodage** — les `.ps1` sont en **ASCII pur**, y compris dans les
commentaires. Deux raisons cumulées : PowerShell 5.1 lit un `.ps1` sans BOM
comme de l'ANSI, et la console héritée du `.bat` tourne en codepage OEM. Les
accents y sortiraient cassés. Les `.ini` et le `readme.txt`, eux, sont en
UTF-8 avec accents — ils sont lus par un humain dans le Bloc-notes, jamais
affichés dans la console.

**Sortie console** — sans accents, pour la même raison.

## Points de conception à préserver

**Aucun chemin d'installation dans la config.** Au moment de fermer un
processus, le moteur relève son chemin réel (`Process.Path`, repli sur WMI pour
les processus plus privilégiés) et l'enregistre. `restore-all` relance
exactement ça. C'est ce qui rend le même `config.ini` utilisable sur n'importe
quelle machine — ne jamais réintroduire de chemin en dur.

**État dans `state/`** — le sous-dossier contient `last-session.json` (ce qui a
été fermé) et `detected-games.json` (cache de détection). Le dossier du projet
reste ainsi autonome et déplaçable d'un bloc. Le dossier est versionné via un
`.gitkeep`, son contenu jamais : `.gitignore` porte `state/*` puis
`!state/.gitkeep`, dans cet ordre — ignorer `state/` en entier empêcherait git
de voir le `.gitkeep`.

Rien de volatil ne doit atterrir ailleurs que là, et rien de volatil ne doit
être versionné.

**La question avant la casse** — si une vérification échoue, on demande avant
d'avoir fermé quoi que ce soit. Annuler ne doit jamais rien coûter.

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

## Fusion config.ini + config.local.ini

`Merge-Ini` applique le local par-dessus la base, ligne par ligne, sans savoir
si la section est une liste ou un jeu de clés :

- `StartTimeout = 60` → remplace la clé existante
- `Discord.exe` → ajoute l'entrée
- `-Spotify.exe` → retire l'entrée de la base

L'identité d'une ligne est donnée par `Get-IniKey` : la partie à gauche du `=`
s'il y en a un, la ligne entière sinon. C'est ce qui permet de traiter listes
et réglages avec le même code. Ajouter une ligne ne doit jamais obliger à
recopier une section entière.

Le parseur est insensible à la casse et tolère `oui/yes/1/on` en plus de
`true/false`, mais tout ce qui est livré et documenté utilise `true/false`.

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
