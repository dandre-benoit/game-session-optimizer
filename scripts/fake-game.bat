@echo off
:: ===============================================================
::  Faux jeu, pour tester l'outil sans lancer une vraie partie.
::  Il ne fait rien d'autre qu'attendre : fermez cette fenetre ou
::  appuyez sur une touche pour simuler la fin du jeu.
:: ===============================================================

chcp 65001 >nul
title Faux jeu (test)
mode con: cols=64 lines=12
color 0A

echo.
echo   ===========================================================
echo     FAUX JEU EN COURS
echo   ===========================================================
echo.
echo   Tout ce qui devait être fermé l'a été, et la session est
echo   enregistrée. Cette fenêtre tient le rôle du jeu.
echo.
echo   Appuyez sur une touche : l'outil doit alors détecter la
echo   fin de la partie et tout remettre en place.
echo.

pause >nul
exit
