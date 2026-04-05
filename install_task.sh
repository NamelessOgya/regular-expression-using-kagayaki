#!/usr/bin/env bash
set -e

echo "Installing go-task to ~/.local/bin without root privileges..."
mkdir -p ~/.local/bin
sh -c "$(wget -qO- https://taskfile.dev/install.sh)" -- -d -b ~/.local/bin

if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    echo "Added ~/.local/bin to PATH in ~/.bashrc"
fi

echo ""
echo "=========================================================="
echo "Installation complete!"
echo "Please run the following command to make 'task' available:"
echo "source ~/.bashrc"
echo "=========================================================="
