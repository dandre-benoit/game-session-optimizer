===============================================================================
  GAME SESSION OPTIMIZER
  Préparer le PC avant une partie, tout remettre en place après
===============================================================================

Ce petit outil ferme ce qui tourne en arrière-plan (navigateurs, utilitaires,
synchronisation, indexation Windows...), vérifie que la machine est en état,
puis lance le jeu. Quand vous quittez le jeu, il remet tout comme avant.

Rien à installer : tout repose sur ce qui est déjà présent dans Windows.


-------------------------------------------------------------------------------
 1. UTILISATION
-------------------------------------------------------------------------------

  Double-cliquez sur "play-bf6.bat"

C'est tout, il n'y a rien à faire d'autre. Le PC est préparé, le jeu se lance,
et à la fin de la partie tout se rouvre automatiquement.

Une fenêtre noire reste ouverte pendant que vous jouez : c'est normal, elle
attend la fermeture du jeu pour faire la restauration. Vous pouvez la réduire
ou l'ignorer, elle est derrière le jeu.

Si vous la fermez quand même, rien n'est perdu : double-cliquez sur
"restore-all.bat", qui fait exactement la même chose à la demande. C'est aussi
le raccourci à utiliser si vous préférez désactiver l'automatisme (voir
AutoRestore dans [Options]).

Si une vérification échoue (Secure Boot désactivé, par exemple), la question
est posée AVANT que quoi que ce soit ne soit fermé : répondre non n'a alors
aucune conséquence.


-------------------------------------------------------------------------------
 2. PREMIÈRE UTILISATION
-------------------------------------------------------------------------------

Le jeu est cherché automatiquement au premier lancement (registre Windows,
bibliothèques Steam, dossiers habituels des launchers). Cela prend quelques
secondes une seule fois, le résultat étant ensuite mémorisé.

Si le jeu n'est pas trouvé, ouvrez "config.ini" avec le Bloc-notes et
remplacez "auto" par le chemin complet de l'exécutable :

    BF6 = D:\Jeux\Battlefield 6\bf6.exe

Le reste fonctionne sans réglage : les applications listées dans config.ini
mais absentes de votre PC sont simplement ignorées.


-------------------------------------------------------------------------------
 3. PERSONNALISER
-------------------------------------------------------------------------------

Il y a deux fichiers de configuration :

    config.ini          la base commune, livrée avec l'outil
    config.local.ini    vos différences à vous — facultatif, jamais versionné

Le second l'emporte sur le premier. C'est celui à utiliser : une mise à jour de
l'outil ne peut pas l'écraser, et vous n'y écrivez que ce qui vous est propre.
Pour démarrer, copiez "config.local.exemple.ini" sous le nom "config.local.ini".

Trois façons d'y intervenir, valables dans n'importe quelle section :

    CloseTimeout = 12        un réglage déjà présent est REMPLACÉ
    Discord.exe              une entrée absente est AJOUTÉE
    -Spotify.exe             le "-" RETIRE une entrée de la base

Il n'est donc jamais nécessaire de recopier une section entière.

Les sections, elles, sont les mêmes dans les deux fichiers :

    [Games]             les jeux et leur emplacement
    [CloseGracefully]   applications à fermer gentiment (elles ont de quoi
                        sauvegarder : navigateur, messagerie, éditeur...)
    [CloseForced]       utilitaires sans fenêtre, arrêtés directement
    [Services]          services Windows à arrêter (serveur local, etc.)
    [Arguments]         arguments à réutiliser au redémarrage
    [Options]           délais et interrupteurs true / false
    [Game.<NOM>]        réglages propres à un jeu

Vous n'avez jamais à indiquer le chemin d'installation d'une application : il
est relevé automatiquement au moment de la fermeture, et réutilisé tel quel au
redémarrage. C'est ce qui rend le même config.ini utilisable sur n'importe
quel PC.


-------------------------------------------------------------------------------
 4. AJOUTER UN JEU
-------------------------------------------------------------------------------

Deux étapes :

  1. Dans "config.ini", sous [Games], ajoutez une ligne :

         MONJEU = auto

  2. Copiez "play-bf6.bat", renommez la copie en "play-monjeu.bat", ouvrez-la
     au Bloc-notes et remplacez BF6 par MONJEU sur la ligne qui commence par
     "powershell".

Si la recherche automatique ne connaît pas ce jeu, indiquez directement son
chemin à l'étape 1 à la place de "auto".

Facultatif : ajoutez une section [Game.MONJEU] pour choisir les vérifications
qui le concernent. TPM 2.0 et Secure Boot, par exemple, ne sont exigés que par
les jeux dont l'anticheat travaille au niveau du noyau.


-------------------------------------------------------------------------------
 5. QUESTIONS COURANTES
-------------------------------------------------------------------------------

« Un service n'a pas pu être arrêté »
    Certains services demandent les droits administrateur. Le lancement se
    poursuit normalement ; pour les arrêter aussi, faites un clic droit sur le
    raccourci > Exécuter en tant qu'administrateur.

« Le jeu n'est pas apparu après 30 s »
    Le launcher (EA, Steam, Battle.net...) attend probablement une connexion ou
    installe une mise à jour. Rien n'est cassé. Vous pouvez augmenter le délai
    avec StartTimeout dans [Options].

« Une application ne redémarre pas »
    Elle a peut-être été déplacée ou désinstallée depuis la partie. Relancez-la
    à la main une fois : le prochain cycle relèvera le nouveau chemin.

« Tout s'est rouvert alors que je jouais encore »
    Le launcher a relancé le jeu (mise à jour, retour au menu) et l'outil a cru
    la partie finie. Augmentez AutoRestoreDelay dans [Options] : c'est le temps
    qu'il observe après la disparition du jeu avant de conclure.

« Je préfère décider moi-même quand tout se rouvre »
    Passez AutoRestore à false dans [Options]. La fenêtre se fermera aussitôt
    le jeu lancé, et "restore-all.bat" restera là pour la restauration.

« Le jeu que je lance est un jeu Steam »
    Passez StopSteam à false dans [Options], sinon Steam sera fermé juste
    avant d'en avoir besoin.


-------------------------------------------------------------------------------
 6. LES FICHIERS
-------------------------------------------------------------------------------

    play-bf6.bat                raccourci de lancement (un par jeu)
    play-mw4.bat                idem
    restore-all.bat             restauration manuelle (filet de secours)
    config.ini                  la configuration de base
    config.local.ini            vos personnalisations (à créer, facultatif)
    config.local.exemple.ini    le modèle à copier pour la créer
    session.ps1                 le moteur — aucune raison de l'ouvrir
    preflight.ps1               les vérifications matérielles
    readme.txt                  ce fichier

    state\                      ce que l'outil retient d'une partie à l'autre

Ces fichiers doivent rester ensemble dans le même dossier, où que vous le
placiez. Le sous-dossier "state" contient ce qui a été fermé et l'emplacement
des jeux trouvés ; il se remplit tout seul et n'a pas à être touché. Rien
n'est écrit ailleurs sur votre PC : déplacer ou supprimer le dossier suffit à
tout emporter, ou à tout effacer.
