@echo off
:: ===============================================================
::  Raccourci de lancement. Rien a configurer ici : la logique est
::  dans session.ps1, les reglages dans config.ini.
::
::  Pour ajouter un jeu : copiez ce fichier, renommez-le, et changez
::  le nom apres -Game. Ce nom doit correspondre a une ligne de la
::  section [Jeux] de config.ini.
::
::  NB : aucun bloc if ( ... ) ici. Si ce dossier etait place dans un
::  chemin contenant des parentheses, comme "Program Files (x86)",
::  la substitution de %~dp0 fermerait le bloc trop tot : erreur de
::  syntaxe, et la fenetre se fermerait d'un coup. D'ou les goto.
:: ===============================================================

title Mode jeu - BF6

if not exist "%~dp0session.ps1" goto :Manquant
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0session.ps1" -Game BF6
exit /b %errorlevel%

:Manquant
echo.
echo ERREUR : session.ps1 est introuvable a cote de ce raccourci.
echo          Les fichiers doivent rester ensemble dans le meme dossier.
echo.
pause
exit /b 2
