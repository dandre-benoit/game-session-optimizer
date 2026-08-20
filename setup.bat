@echo off
:: ===============================================================
::  Double-cliquez sur ce fichier pour creer les raccourcis sur
::  votre Bureau : un par jeu declare dans config.ini, un pour
::  tout rouvrir apres la partie, et -- si TestShortcut vaut true
::  -- un raccourci "Tester ma configuration".
::
::  A relancer chaque fois que vous ajoutez un jeu dans config.ini.
::
::  NB : aucun bloc if ( ... ) ici. Si ce dossier etait place dans
::  un chemin contenant des parentheses, comme "Program Files
::  (x86)", la substitution de %~dp0 fermerait le bloc trop tot :
::  erreur de syntaxe, et la fenetre se fermerait d'un coup.
::  D'ou les goto.
::
::  Pas de chcp ni d'accents ici : changer de page de code en cours
::  d'execution decale l'offset de lecture de cmd.exe, qui tronque
::  alors le debut des lignes suivantes et casse les goto. Les
::  accents sont geres par les scripts PowerShell, qui forcent
::  eux-memes leur encodage de sortie.
:: ===============================================================

title Game Session Optimizer - installation

if not exist "%~dp0scripts\setup.ps1" goto :Manquant
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup.ps1"
exit /b %errorlevel%

:Manquant
echo.
echo ERREUR : scripts\setup.ps1 est introuvable.
echo          Le dossier scripts doit rester a cote de ce fichier.
echo.
pause
exit /b 2