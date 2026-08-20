@echo off
:: ===============================================================
::  Faux jeu, pour tester l'outil sans lancer une vraie partie.
::  Il ne fait rien d'autre qu'attendre : fermez cette fenetre ou
::  appuyez sur une touche pour simuler la fin du jeu.
:: ===============================================================

title Faux jeu (test)
mode con: cols=64 lines=12
color 0A

echo.
echo   ===========================================================
echo     FAUX JEU EN COURS
echo   ===========================================================
echo.
echo   Tout ce qui devait etre ferme l'a ete, et la session est
echo   enregistree. Cette fenetre tient le role du jeu.
echo.
echo   Appuyez sur une touche : l'outil doit alors detecter la
echo   fin de la partie et tout remettre en place.
echo.

pause >nul
exit /b 0