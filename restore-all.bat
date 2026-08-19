@echo off
:: ===============================================================
::  Remet la machine dans l'etat d'avant la partie : redemarre les
::  services arretes et les applications fermees par le dernier
::  "play-<jeu>.bat".
::
::  Aucun chemin a saisir : ils ont ete releves automatiquement au
::  moment de la fermeture.
::
::  NB : pas de bloc if ( ... ), voir l'explication dans "play-bf6.bat".
:: ===============================================================

title Mode jeu - restauration

if not exist "%~dp0session.ps1" goto :Manquant
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0session.ps1" -Restore
exit /b %errorlevel%

:Manquant
echo.
echo ERREUR : session.ps1 est introuvable a cote de ce raccourci.
echo          Les fichiers doivent rester ensemble dans le meme dossier.
echo.
pause
exit /b 2
