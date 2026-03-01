#!/bin/bash

echo "=========================================="
echo "Flutter Setup Helper for Windows/Git Bash"
echo "=========================================="
echo ""

# Check if Flutter is already installed
if command -v flutter &> /dev/null; then
    echo "✓ Flutter is already installed!"
    flutter --version
    exit 0
fi

echo "Flutter is not installed or not in PATH."
echo ""
echo "STEP 1: Download Flutter"
echo "------------------------"
echo "1. Open your browser and go to:"
echo "   https://docs.flutter.dev/get-started/install/windows"
echo ""
echo "2. Download the Flutter SDK (ZIP file)"
echo ""
echo "3. Extract the ZIP file to a location like:"
echo "   C:\\src\\flutter"
echo "   (or any location you prefer)"
echo ""
read -p "Press Enter after you've downloaded and extracted Flutter..."

echo ""
echo "STEP 2: Configure PATH"
echo "----------------------"
echo ""

# Get the Flutter installation path from user
read -p "Enter the path where you extracted Flutter (e.g., /c/src/flutter): " FLUTTER_PATH

# Check if the path exists
if [ ! -d "$FLUTTER_PATH" ]; then
    echo "Error: Directory '$FLUTTER_PATH' does not exist!"
    echo "Please make sure you've extracted Flutter to that location."
    exit 1
fi

# Check if flutter binary exists
if [ ! -f "$FLUTTER_PATH/bin/flutter" ]; then
    echo "Error: Flutter binary not found at '$FLUTTER_PATH/bin/flutter'"
    echo "Please check the path and make sure Flutter is extracted correctly."
    exit 1
fi

echo ""
echo "✓ Flutter found at: $FLUTTER_PATH"
echo ""

# Determine bashrc location
BASHRC_FILE="$HOME/.bashrc"
if [ ! -f "$BASHRC_FILE" ]; then
    echo "Creating $BASHRC_FILE..."
    touch "$BASHRC_FILE"
fi

# Check if PATH is already set
if grep -q "flutter/bin" "$BASHRC_FILE"; then
    echo "Flutter PATH already configured in $BASHRC_FILE"
    echo "Updating it..."
    # Remove old Flutter PATH entries
    sed -i '/flutter\/bin/d' "$BASHRC_FILE"
fi

# Add Flutter to PATH
echo "" >> "$BASHRC_FILE"
echo "# Flutter SDK" >> "$BASHRC_FILE"
echo "export PATH=\"\$PATH:$FLUTTER_PATH/bin\"" >> "$BASHRC_FILE"

echo "✓ Added Flutter to PATH in $BASHRC_FILE"
echo ""
echo "STEP 3: Reload PATH"
echo "-------------------"
echo "Reloading your bash configuration..."
source "$BASHRC_FILE"

# Verify installation
if command -v flutter &> /dev/null; then
    echo ""
    echo "✓ Flutter is now installed and configured!"
    echo ""
    echo "Flutter version:"
    flutter --version
    echo ""
    echo "Running Flutter doctor to check setup:"
    flutter doctor
else
    echo ""
    echo "⚠ Flutter command not found. Please:"
    echo "1. Close and reopen your terminal, or"
    echo "2. Run: source ~/.bashrc"
    echo ""
    echo "Then verify with: flutter --version"
fi


