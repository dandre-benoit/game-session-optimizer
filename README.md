# Game Session Optimizer

**Préparer le PC avant une partie, tout remettre en place après.**

Cet outil ferme les applications qui tournent en arrière-plan — navigateur,
messagerie, synchronisation, indexation Windows — vérifie que la machine est en
état de jouer, puis lance le jeu. Quand vous le quittez, tout est remis comme
avant, à sa place.

Rien à installer : il n'utilise que ce qui est déjà présent dans Windows 10 et 11.

---

## Prérequis

**Windows 10 ou 11.** C'est tout côté machine — aucun logiciel à installer pour
faire fonctionner l'outil.

**Git**, uniquement pour récupérer le dossier et recevoir les mises à jour.
Pas besoin de savoir s'en servir : deux copier-coller suffisent, et vous n'y
retoucherez plus.

1. Téléchargez-le sur **[git-scm.com/download/win](https://git-scm.com/download/win)**
   et installez-le en laissant toutes les options par défaut (cliquez
   « Next » jusqu'au bout).

2. Choisissez où mettre l'outil — vos Documents, par exemple. Ouvrez ce dossier
   dans l'Explorateur, faites un clic droit dans le vide, puis **« Ouvrir le
   terminal »** ou **« Git Bash Here »**. Collez ceci et appuyez sur Entrée :

   ```
   git clone https://github.com/<compte>/game-session-optimizer.git
   ```

   Un dossier `game-session-optimizer` apparaît. Vous pouvez fermer la fenêtre
   noire : le reste se fait à la souris.

3. Plus tard, pour récupérer les améliorations, rouvrez le terminal **dans le
   dossier** `game-session-optimizer` et collez :

   ```
   git pull
   ```

   Votre `config.ini` n'est jamais touché par une mise à jour.

> Si vous préférez éviter git : sur la page du projet, bouton vert **Code** puis
> **Download ZIP**, et décompressez où vous voulez. L'outil fonctionne
> pareil — simplement, `git pull` ne sera pas disponible et il faudra
> retélécharger le ZIP à chaque mise à jour.

---

## Installation

> Double-cliquez sur **`setup.bat`**

Il crée sur votre Bureau un raccourci par jeu — **Lancer Battlefield 6**,
**Lancer Call of Duty 4 - Modern Warfare**… — chacun avec l'icône du jeu, plus
un raccourci **Tout rouvrir**.

C'est aussi ce qu'il faut relancer après avoir ajouté un jeu dans `config.ini` :
les raccourcis sont simplement refaits.

Pour les ranger ailleurs que sur le Bureau, renseignez `ShortcutFolder` dans
`[Options]` — les variables d'environnement sont acceptées, et un chemin
relatif part du dossier de l'outil :

```ini
ShortcutFolder = %USERPROFILE%\Desktop\Mes Jeux
```

Si vous changez d'avis, les raccourcis de l'ancien emplacement sont retirés à la
relance suivante.

Un jeu que l'outil ne trouve pas n'obtient pas de raccourci — il ne servirait à
rien. Le setup vous le dit à la fin : soit le jeu n'est pas installé, soit il
faut indiquer son chemin dans `config.ini` puis relancer.

## Utilisation

> Double-cliquez sur **Lancer Battlefield 6**, sur votre Bureau

C'est tout. Le PC est préparé, le jeu se lance, et à la fin de la partie tout se
rouvre automatiquement.

Une fenêtre noire reste ouverte pendant que vous jouez : c'est normal, elle
attend la fermeture du jeu pour faire la restauration. Vous pouvez la réduire ou
l'ignorer, elle est derrière le jeu.

Si vous la fermez quand même, rien n'est perdu : le raccourci **Tout rouvrir**
fait exactement la même chose à la demande. C'est aussi celui à utiliser si vous
préférez désactiver l'automatisme (voir `AutoRestore`).

Si une vérification échoue — Secure Boot désactivé, par exemple — la question
est posée **avant** que quoi que ce soit ne soit fermé : répondre non n'a alors
aucune conséquence.

## Première utilisation

Le jeu est cherché automatiquement au premier lancement : registre Windows,
bibliothèques Steam, dossiers habituels des launchers. Cela prend quelques
secondes une seule fois, le résultat étant ensuite mémorisé.

S'il n'est pas trouvé, ouvrez `config.ini` et remplacez `auto` par le chemin
complet de l'exécutable :

```ini
[Games]
BF6 = D:\Jeux\Battlefield 6\bf6.exe
```

Le reste fonctionne sans réglage : les applications listées dans `config.ini`
mais absentes de votre PC sont simplement ignorées.

## Personnaliser

Tout se passe dans **`config.ini`**, modifiable au Bloc-notes. Il n'est pas
livré avec l'outil : il est créé automatiquement au premier lancement, à partir
de `config.exemple.ini`. C'est le vôtre, une mise à jour ne l'écrasera pas.

| Fichier | Rôle |
|---|---|
| `config.ini` | votre configuration — le seul fichier que le programme lit |
| `config.exemple.ini` | le modèle d'origine, pour repartir de zéro ou comparer |

Les sections :

| Section | Contenu |
|---|---|
| `[Games]` | les jeux et leur emplacement |
| `[CloseGracefully]` | applications à fermer gentiment — elles ont de quoi sauvegarder : navigateur, messagerie, éditeur… ainsi que les plateformes de jeu |
| `[CloseForced]` | utilitaires sans fenêtre, arrêtés directement |
| `[Services]` | services Windows à arrêter (serveur local, etc.) |
| `[Arguments]` | arguments à réutiliser au redémarrage |
| `[Options]` | délais et interrupteurs `true` / `false` |
| `[Game.<NOM>]` | réglages propres à un jeu : vérifications, launcher |

Vous n'avez **jamais** à indiquer le chemin d'installation d'une application :
il est relevé automatiquement au moment de la fermeture, puis réutilisé tel quel
au redémarrage. C'est ce qui rend le même `config.ini` utilisable sur n'importe
quel PC.

### Les plateformes de jeu

Steam, Battle.net, le launcher EA, Epic — ils figurent dans `[CloseGracefully]`
comme les autres applications, mais avec une exception : **celle dont votre jeu
a besoin ne doit pas être fermée**, sinon le jeu ne démarre pas.

Indiquez-la dans la section du jeu :

```ini
[Game.MW4]
Launcher = Battle.net.exe
```

Le programme ferme alors toutes les autres et laisse celle-là tranquille. La
valeur se déclare par jeu parce qu'elle dépend de l'endroit où vous l'avez
acheté : le même jeu pris sur Steam demanderait `Launcher = steam.exe`.

## Ajouter un jeu

1. Dans `config.ini`, sous `[Games]`, ajoutez une ligne :

   ```ini
   MONJEU = auto
   ```

2. Ajoutez une section `[Game.MONJEU]` avec au moins son launcher :

   ```ini
   [Game.MONJEU]
   Launcher = steam.exe
   Checks = SecureBoot, ResizableBAR, NvidiaDriver, DiskSpace
   ```

3. Double-cliquez sur `setup.bat` : le raccourci **Lancer MONJEU** apparaît sur
   le Bureau.

Si la recherche automatique ne connaît pas ce jeu, indiquez directement son
chemin à l'étape 1 à la place de `auto`.

`Checks` est facultatif : sans lui, les vérifications par défaut s'appliquent.
TPM 2.0 et Secure Boot, par exemple, ne sont exigés que par les jeux dont
l'anticheat travaille au niveau du noyau.

Vérifications disponibles : `TPM`, `SecureBoot`, `ResizableBAR`,
`NvidiaDriver`, `DiskSpace`. Une vérification qui ne s'applique pas à la machine
— pas de carte NVIDIA, par exemple — est signalée `?` et n'empêche pas le
lancement.

## Questions courantes

**Un service n'a pas pu être arrêté**
Certains services demandent les droits administrateur. Le lancement se poursuit
normalement ; pour les arrêter aussi, clic droit sur le raccourci >
*Exécuter en tant qu'administrateur*.

**Le jeu n'est pas apparu après 30 s**
Le launcher (EA, Steam, Battle.net…) attend probablement une connexion ou
installe une mise à jour. Rien n'est cassé. Augmentez `StartTimeout` dans
`[Options]`.

**Une application ne redémarre pas**
Elle a peut-être été déplacée ou désinstallée depuis la partie. Relancez-la à la
main une fois : le prochain cycle relèvera le nouveau chemin.

**Tout s'est rouvert alors que je jouais encore**
Le launcher a relancé le jeu (mise à jour, retour au menu) et l'outil a cru la
partie finie. Augmentez `AutoRestoreDelay` : c'est le temps qu'il observe après
la disparition du jeu avant de conclure.

**Je préfère décider moi-même quand tout se rouvre**
Passez `AutoRestore` à `false`. La fenêtre se fermera aussitôt le jeu lancé, et
le raccourci **Tout rouvrir** restera là pour la restauration.

**J'ai déplacé le dossier et les raccourcis ne marchent plus**
Ils pointent vers l'ancien emplacement. Relancez `setup.bat` depuis le nouveau.

**Le jeu ne démarre plus depuis que j'utilise l'outil**
Sa plateforme a probablement été fermée juste avant le lancement. Ajoutez
`Launcher = ...` dans la section du jeu — voir *Les plateformes de jeu*.

## Les fichiers

| Fichier | Rôle |
|---|---|
| `setup.bat` | crée les raccourcis du Bureau — à relancer après un ajout de jeu |
| `config.ini` | votre configuration — créée au premier lancement |
| `config.exemple.ini` | le modèle d'origine |
| `session.ps1` | le moteur — aucune raison de l'ouvrir |
| `setup.ps1` | ce que `setup.bat` exécute |
| `preflight.ps1` | les vérifications matérielles |
| `state.json` | ce que l'outil retient d'une partie à l'autre |

Ces fichiers doivent rester ensemble dans le même dossier, où que vous le
placiez. `state.json` contient ce qui a été fermé et l'emplacement des jeux
trouvés ; il se crée tout seul et n'a pas à être touché — le supprimer ne casse
rien, il se reconstruira.

Rien n'est écrit ailleurs sur votre PC : déplacer ou supprimer le dossier suffit
à tout emporter, ou à tout effacer.
