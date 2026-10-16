#!/bin/bash
# Build script for Android with obfuscation

echo "Building Android AppBundle with obfuscation..."
flutter build appbundle --release --obfuscate --split-debug-info=build/app/outputs/symbols

echo "Build complete! Symbols are saved in build/app/outputs/symbols"
