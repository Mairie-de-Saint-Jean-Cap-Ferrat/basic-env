---
name: Environnement de développement de base
description: Environnement de base avec code-server.
tags: [local, docker]
---

# Templates Coder - Environnements de Développement

Ce projet fournit des templates prêts à l'emploi pour [Coder](https://coder.com/) qui créent des environnements de développement cohérents. Tous les environnements sont construits à partir d'une image de base commune et offrent des outils spécifiques à chaque langage.

## Templates Disponibles

* **Base** - Environnement fondamental avec des outils de développement communs
* **JavaScript** - Environnement de développement Node.js
  * Avec [nvm](https://github.com/nvm-sh/nvm/blob/master/README.md) pour la gestion des versions de Node.js
* **TypeScript** - Environnement de développement TypeScript
* **PHP** - Environnement de développement PHP
* **Java** - Environnement de développement Java
  * Inclut sdkman pour la gestion des versions Java
* **Python** - Environnement de développement Python
* **Dart** - Environnement de développement Dart

## Fonctionnalités Communes

Tous les environnements comprennent:

* **VS Code Server** - Le `vscode-server` de Microsoft avec des extensions du Marketplace d'Extensions Microsoft
* **Dotfiles** - Personnalisez votre environnement avec des dotfiles
* **Accès VNC** - Environnement de bureau XFCE accessible via noVNC
* **Configuration Git** - Paramètres Git personnalisables
* **Basé sur conteneurs** - Environnements isolés et reproductibles utilisant Docker

## Démarrage

Cliquez sur le bouton "Create workspace" dans Coder pour sélectionner l'un des templates disponibles.

**OU**

Exécutez `coder templates init` et sélectionnez ce template. Suivez les instructions qui s'affichent.

## Remarques

Consultez [NOTES.md](./NOTES.md) pour des exigences et des détails de configuration supplémentaires.
