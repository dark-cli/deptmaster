#!/bin/bash
# Generate Hive adapters for Event model

cd "$(dirname "$0")"
flutter pub run build_runner build --delete-conflicting-outputs
