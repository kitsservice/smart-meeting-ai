@echo off
echo Building Android AppBundle with obfuscation...

call flutter build appbundle --release --obfuscate --split-debug-info=build\app\outputs\symbols

echo Build complete! Symbols are saved in build\app\outputs\symbols
pause
