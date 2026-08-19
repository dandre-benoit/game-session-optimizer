# Game Session Optimizer

**Préparer le PC avant une partie, tout remettre en place après.**

Cet outil ferme ce qui tourne en arrière-plan (navigateurs, utilitaires,
synchronisation, indexation Windows…), vérifie que la machine est en état, puis
lance le jeu. Quand vous quittez le jeu, il remet tout comme avant.

Rien à installer : tout repose sur ce qui est déjà présent dans Windows 10 et 11.

---

## Utilisation

> Double-cliquez sur **`play-bf6.bat`**

C'est tout. Le PC est préparé, le jeu se lance, et à la fin de la partie tout se
rouvre automatiquement.

Une fenêtre noire reste ouverte pendant que vous jouez : c'est normal, elle
attend la fermeture du jeu pour faire la restauration. Vous pouvez la réduire ou
l'ignorer, elle est derrière le jeu.

Si vous la fermez quand même, rien n'est perdu : double-cliquez sur
**`restore-all.bat`**, qui fait exactement la même chose à la demande. C'est
aussi le raccourci à utiliser si vous préférez désactiver l'automatisme (voir
`AutoRestore`).

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

2. Copiez `play-bf6.bat`, renommez la copie en `play-monjeu.bat`, et remplacez
   `BF6` par `MONJEU` sur la ligne qui commence par `powershell`.

3. Ajoutez une section `[Game.MONJEU]` avec au moins son launcher :

   ```ini
   [Game.MONJEU]
   Launcher = steam.exe
   Checks = SecureBoot, ResizableBAR, NvidiaDriver, DiskSpace
   ```

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
`restore-all.bat` restera là pour la restauration.

**Le jeu ne démarre plus depuis que j'utilise l'outil**
Sa plateforme a probablement été fermée juste avant le lancement. Ajoutez
`Launcher = ...` dans la section du jeu — voir *Les plateformes de jeu*.

## Les fichiers

| Fichier | Rôle |
|---|---|
| `play-bf6.bat` · `play-mw4.bat` | raccourcis de lancement, un par jeu |
| `restore-all.bat` | restauration manuelle (filet de secours) |
| `config.ini` | votre configuration — créée au premier lancement |
| `config.exemple.ini` | le modèle d'origine |
| `session.ps1` | le moteur — aucune raison de l'ouvrir |
| `preflight.ps1` | les vérifications matérielles |
| `state\` | ce que l'outil retient d'une partie à l'autre |

Ces fichiers doivent rester ensemble dans le même dossier, où que vous le
placiez. Le sous-dossier `state` contient ce qui a été fermé et l'emplacement
des jeux trouvés ; il se remplit tout seul et n'a pas à être touché.

Rien n'est écrit ailleurs sur votre PC : déplacer ou supprimer le dossier suffit
à tout emporter, ou à tout effacer.
