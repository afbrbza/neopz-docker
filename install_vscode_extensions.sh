#!/usr/bin/env bash

echo "Installing VSCode extensions..."

for ext in \
ms-vscode.cpptools \
ms-vscode.cmake-tools \
ms-azuretools.vscode-containers \
ms-vscode-remote.remote-containers
do
    code --list-extensions | grep -q "^$ext$" || code --install-extension "$ext"
done

echo "VSCode extensions installed."