@echo off
:: ===============================================================
::  Double-cliquez sur ce fichier pour creer les raccourcis sur
::  votre Bureau : un par jeu, plus un raccourci de restauration.
::
::  A relancer chaque fois que vous ajoutez un jeu dans config.ini.
::
::  NB : aucun bloc if ( ... ) ici. Si ce dossier etait place dans
::  un chemin contenant des parentheses, comme "Program Files
::  (x86)", la substitution de %~dp0 fermerait le bloc trop tot :
::  erreur de syntaxe, et la fenetre se fermerait d'un coup.
::  D'ou les goto.
:: ===============================================================

title Game Session Optimizer - installation

if not exist "%~dp0setup.ps1" goto :Manquant
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
exit /b %errorlevel%

:Manquant
echo.
echo ERREUR : setup.ps1 est introuvable a cote de ce fichier.
echo          Les fichiers doivent rester ensemble dans le meme dossier.
echo.
pause
exit /b 2
