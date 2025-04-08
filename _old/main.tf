terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
    }

    docker = {
      source  = "kreuzwerker/docker"
    }

    envbuilder = {
      source = "coder/envbuilder"
    }
  }
}

locals {
  enable_subdomains = true

  workspace_name = lower(data.coder_workspace.me.name)
  user_name = lower(data.coder_workspace_owner.me.name)

  images = {
    javascript = docker_image.javascript
    typescript = docker_image.typescript
    php = docker_image.php
    java = docker_image.java
    python = docker_image.python
    dart = docker_image.dart
    base = docker_image.base
  }
  
  # Flag to control GitHub integration
  github_auth_enabled = false
  
  # Owner related attributes to replace deprecated ones
  owner_name = data.coder_workspace_owner.me.name
  owner_email = data.coder_workspace_owner.me.email
  owner_session_token = data.coder_workspace_owner.me.session_token
  
  # Utilisation de devcontainer selon le choix utilisateur
  use_devcontainer = data.coder_parameter.use_devcontainer.value == "true"
  
  # EnvBuilder configuration
  container_name = "coder-${local.user_name}-${local.workspace_name}"
  devcontainer_builder_image = data.coder_parameter.devcontainer_builder.value
  git_author_name = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
  repo_url = data.coder_parameter.git_repository.value
  
  # Extensions VS Code par catégorie
  vscode_extensions = {
    git = [
      "mhutchie.git-graph",
      "donjayamanne.githistory",
      "shyykoserhiy.git-autoconfig",
      "github.vscode-github-actions",
      "GitHub.vscode-pull-request-github",
      "GitHub.remotehub",
      "howardzuo.vscode-git-tags",
      "maciejdems.add-to-gitignore"
    ],
    github_copilot = [
      "GitHub.copilot",
      "GitHub.copilot-chat",
      "ms-vscode.vscode-copilot-vision",
      "ms-azuretools.vscode-azure-github-copilot",
      "ms-vscode.vscode-copilot-data-analysis",
      "GitHub.copilot-workspace",
      "genaiscript.genaiscript-vscode",
      "ms-toolsai.prompty",
      "prompt-flow.prompt-flow"
    ],
    languages = [
      "ms-azuretools.vscode-docker",
      "redhat.vscode-yaml",
      "timonwong.shellcheck",
      "foxundermoon.shell-format"
    ],
    productivity = [
      "aaron-bond.better-comments",
      "usernamehw.errorlens",
      "formulahendry.auto-rename-tag",
      "oderwat.indent-rainbow",
      "vscode-icons-team.vscode-icons",
      "wayou.vscode-todo-highlight",
      "christian-kohler.path-intellisense",
      "EditorConfig.EditorConfig",
      "Gruntfuggly.todo-tree",
      "shardulm94.trailing-spaces"
    ],
    viewers = [
      "GrapeCity.gc-excelviewer",
      "tomoki1207.pdf",
      "adamraichu.docx-viewer",
      "RandomFractalsInc.geo-data-viewer",
      "DutchIgor.json-viewer",
      "berublan.vscode-log-viewer"
    ],
    collaboration = [
      "ms-vsliveshare.vsliveshare",
      "ms-vscode.remote-repositories",
      "ms-vscode-remote.vscode-remote-extensionpack"
    ],
    intelligence = [
      "VisualStudioExptTeam.vscodeintellicode",
      "VisualStudioExptTeam.intellicode-api-usage-examples",
      "VisualStudioExptTeam.vscodeintellicode-completions"
    ],
    server = [
      "ms-vscode.live-server",
      "ritwickdey.LiveServer"
    ]
  }
  
  # Récupération des extensions sélectionnées par l'utilisateur
  selected_extensions = concat(
    data.coder_parameter.vscode_extensions_git.value == "true" ? local.vscode_extensions.git : [],
    data.coder_parameter.vscode_extensions_github_copilot.value == "true" ? local.vscode_extensions.github_copilot : [],
    data.coder_parameter.vscode_extensions_languages.value == "true" ? local.vscode_extensions.languages : [],
    data.coder_parameter.vscode_extensions_productivity.value == "true" ? local.vscode_extensions.productivity : [],
    data.coder_parameter.vscode_extensions_viewers.value == "true" ? local.vscode_extensions.viewers : [],
    data.coder_parameter.vscode_extensions_collaboration.value == "true" ? local.vscode_extensions.collaboration : [],
    data.coder_parameter.vscode_extensions_intelligence.value == "true" ? local.vscode_extensions.intelligence : [],
    data.coder_parameter.vscode_extensions_server.value == "true" ? local.vscode_extensions.server : []
  )
  
  # The envbuilder provider requires a key-value map of environment variables
  envbuilder_env = {
    "ENVBUILDER_GIT_URL" : local.repo_url,
    "ENVBUILDER_CACHE_REPO" : var.cache_repo,
    "CODER_AGENT_TOKEN" : coder_agent.dev.token,
    "CODER_AGENT_URL" : replace(data.coder_workspace.me.access_url, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal"),
    "ENVBUILDER_INIT_SCRIPT" : replace(coder_agent.dev.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal"),
    "ENVBUILDER_FALLBACK_IMAGE" : data.coder_parameter.fallback_image.value,
    "ENVBUILDER_DOCKER_CONFIG_BASE64" : try(data.local_sensitive_file.cache_repo_dockerconfigjson[0].content_base64, ""),
    "ENVBUILDER_PUSH_IMAGE" : var.cache_repo == "" ? "" : "true",
    "ENVBUILDER_INSECURE" : "${var.insecure_cache_repo}",
    "ENVBUILDER_QUICK_START" : "true",                 # Activer le démarrage rapide
    "ENVBUILDER_SKIP_HEALTHCHECK" : "true",            # Ignorer le healthcheck pour accélérer
    "ENVBUILDER_PARALLEL_PULL" : "true",               # Téléchargements parallèles
    "ENVBUILDER_NO_PROGRESS" : "true",                 # Désactiver l'affichage verbeux
    "DOCKER_BUILDKIT" : "1",                           # Activer BuildKit
    "BUILDKIT_PROGRESS" : "plain",                     # Affichage plus simple
    "DOCKER_CLI_EXPERIMENTAL" : "enabled"              # Activer les fonctionnalités expérimentales
  }
  
  # Calculer l'image de secours en fonction des choix utilisateur
  fallback_image = local.use_devcontainer ? data.coder_parameter.fallback_image.value : null

  # Convert the environment variables map to the format expected by the docker provider
  docker_env = [
    for k, v in local.envbuilder_env : "${k}=${v}"
  ]

  # Configuration DNS pour garantir la résolution des noms d'hôtes
  dns_servers = [
    "8.8.8.8",     # Google DNS primaire
    "8.8.4.4",     # Google DNS secondaire
    "1.1.1.1",     # Cloudflare DNS primaire
    "1.0.0.1"      # Cloudflare DNS secondaire
  ]
  
  # Ajout d'une variable pour le timeout Git
  git_timeout_seconds = 30

  # Liste de serveurs de temps NTP
  ntp_servers = [
    "time.google.com",
    "time.cloudflare.com",
    "pool.ntp.org"
  ]

  # Paramètres d'optimisation
  docker_pull_timeout = 300
  build_optimization = {
    use_cache = true
    parallel_downloads = true
    keep_layers = true
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

provider "coder" {}

provider "envbuilder" {
  # Configuration du provider envbuilder
  # Aucun paramètre obligatoire n'est requis pour ce provider
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "random_string" "vnc_password" {
  count   = data.coder_parameter.vnc.value == "true" ? 1 : 0
  length  = 6
  special = false
}

resource "coder_metadata" "vnc_password" {
  count       = data.coder_parameter.vnc.value == "true" ? 1 : 0
  resource_id = random_string.vnc_password[0].id

  hide = true

  item {
    key = "description"
    value = "VNC Password"
  }
}

resource "coder_agent" "dev" {
  arch = "amd64"
  os   = "linux"

  display_apps {
    vscode          = true
    vscode_insiders = true
    web_terminal    = true
    ssh_helper      = true
  }

  env = {
    "VNC_ENABLED"   = data.coder_parameter.vnc.value
    "SHELL"         = data.coder_parameter.shell.value
    "VSCODE_BINARY" = data.coder_parameter.vscode_binary.value
    "GIT_REPO"      = data.coder_parameter.git_repository.value
    "CODER_USER_TOKEN" = local.owner_session_token
    "GIT_USERNAME" = local.owner_name
    "GIT_EMAIL" = local.owner_email
    
    # Git configuration
    "GIT_AUTHOR_NAME"     = local.owner_name
    "GIT_AUTHOR_EMAIL"    = local.owner_email
    "GIT_COMMITTER_NAME"  = local.owner_name
    "GIT_COMMITTER_EMAIL" = local.owner_email
    
    # Configuration améliorée pour Git
    "GIT_HTTP_MAX_RETRIES" = "3"
    "GIT_HTTP_TIMEOUT" = "${local.git_timeout_seconds}"
    "GIT_CONFIG_NOSYSTEM" = "0"
    "GIT_DISCOVERY_ACROSS_FILESYSTEM" = "1"
  }

  startup_script = <<EOT
#!/bin/bash
set -e

echo "[+] Configuration du réseau et DNS"
# Vérifier les serveurs DNS disponibles
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf > /dev/null
echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf > /dev/null
echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf > /dev/null

# Test de connectivité
ping -c 1 github.com || echo "AVERTISSEMENT: Impossible de joindre github.com - vérifiez votre connectivité réseau"

echo "[+] Setting default shell"
SHELL=$(which $SHELL)
sudo chsh -s $SHELL $USER
sudo chsh -s $SHELL root

echo "[+] Optimisation de la configuration Git"
git config --global http.postBuffer 524288000
git config --global http.maxRequestBuffer 100M
git config --global core.compression 0
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 60
git config --global credential.helper 'cache --timeout=3600'
git config --global http.sslVerify false

echo "[+] Starting code-server"
code-server --auth none --port 13337 >/dev/null 2>&1 &

# Clone le dépôt Git spécifié par l'utilisateur
if [ ! -z "$GIT_REPO" ]; then
  echo "[+] Clonage du dépôt Git: $GIT_REPO"
  mkdir -p ~/projects
  cd ~/projects
  
  # Extraction du nom du dépôt depuis l'URL
  REPO_NAME=$(basename "$GIT_REPO" .git)
  
  # Vérification si le répertoire existe déjà
  if [ -d "$REPO_NAME" ]; then
    echo "[*] Le répertoire du dépôt existe déjà, mise à jour..."
    cd "$REPO_NAME"
    git pull || echo "AVERTISSEMENT: échec de git pull - des modifications locales peuvent exister"
  else
    # Clonage avec gestion avancée des erreurs
    echo "[+] Clonage du dépôt avec options avancées..."
    GIT_TERMINAL_PROMPT=0 git clone --depth=1 "$GIT_REPO" \
      --config http.sslVerify=false \
      --config http.postBuffer=524288000 \
      --config core.compression=0 \
      --config http.lowSpeedLimit=1000 \
      --config http.lowSpeedTime=60 \
      || echo "[!] Échec du clonage automatique du dépôt"
      
    # Si le clonage a réussi, vérifier la présence d'une configuration devcontainer
    if [ -d "$REPO_NAME" ]; then
      cd "$REPO_NAME"
      
      # Vérifier si le dépôt contient un fichier devcontainer.json
      if [ -f ".devcontainer/devcontainer.json" ] || [ -f ".devcontainer.json" ]; then
        echo "[+] Configuration devcontainer détectée dans le dépôt"
        
        if [ "${data.coder_parameter.use_devcontainer.value}" = "true" ]; then
          echo "[+] Mode devcontainer activé, utilisation de la configuration du dépôt"
          # Les instructions spécifiques au devcontainer seront gérées par envbuilder
        else
          echo "[*] Mode devcontainer non activé. Pour utiliser la configuration devcontainer, redémarrez l'environnement en activant cette option."
        fi
      else
        echo "[*] Aucune configuration devcontainer trouvée dans le dépôt"
      fi
    fi
  fi
fi

# Only start VNC if enabled
if [ "$VNC_ENABLED" = "true" ]
then
  echo "[+] Starting VNC"
  # Ensure VNC directory exists
  mkdir -p $HOME/.vnc
  
  # Generate VNC password file
  VNC_PWD='${data.coder_parameter.vnc.value == "true" ? random_string.vnc_password[0].result : ""}'
  echo "$VNC_PWD" | tightvncpasswd -f > $HOME/.vnc/passwd
  chmod 600 $HOME/.vnc/passwd
  
  # Kill any existing VNC sessions
  vncserver -kill :1 >/dev/null 2>&1 || true
  
  # Start VNC server with proper configuration
  vncserver :1 -geometry 1920x1080 -depth 24 -localhost no >/dev/null 2>&1
  
  # Wait a moment for VNC server to initialize
  sleep 2
  
  # Start noVNC with proper configuration
  /usr/share/novnc/utils/launch.sh --vnc localhost:5901 --listen 6080 --web /usr/share/novnc >/dev/null 2>&1 &
  
  echo "[+] VNC server started with password: $VNC_PWD"
  echo "[+] Access via browser at: http://localhost:6080/vnc.html"
fi

# Synchronisation de l'heure du système pour éviter les problèmes avec Git
echo "[+] Synchronisation de l'heure système"
sudo ntpdate -u ${local.ntp_servers[0]} || sudo ntpdate -u ${local.ntp_servers[1]} || sudo ntpdate -u ${local.ntp_servers[2]} || true

# Création d'un fichier de statut pour le monitoring
mkdir -p $HOME/.coder
cat > $HOME/.coder/status.json <<EOF
{
  "workspace": {
    "name": "${local.workspace_name}",
    "owner": "${local.user_name}",
    "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "image": "${local.use_devcontainer ? "devcontainer" : data.coder_parameter.docker_image.value}",
    "git_repo": "${data.coder_parameter.git_repository.value}",
    "devcontainer_enabled": "${data.coder_parameter.use_devcontainer.value}"
  }
}
EOF

echo "[+] Configuration terminée avec succès"
EOT

  # Monitoring metadata blocks
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $HOME"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # get load avg scaled by number of cores
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }

  metadata {
    display_name = "Swap Usage (Host)"
    key          = "7_swap_host"
    script       = <<EOT
      free -b | awk '/^Swap/ { printf("%.1f/%.1f", $3/1024.0/1024.0/1024.0, $2/1024.0/1024.0/1024.0) }'
    EOT
    interval     = 10
    timeout      = 1
  }
}

# Cache variables pour des builds plus rapides
variable "cache_repo" {
  default     = ""
  description = "URL du registre Docker à utiliser comme cache pour accélérer les builds de devcontainer"
  type        = string
}

variable "insecure_cache_repo" {
  default     = false
  description = "Activez cette option si votre registre de cache n'utilise pas HTTPS"
  type        = bool
}

variable "cache_repo_docker_config_path" {
  default     = ""
  description = "Chemin vers un fichier docker config.json contenant les identifiants pour le registre cache"
  sensitive   = true
  type        = string
}

# Paramètres organisés en sections logiques
# 1. Choix du dépôt Git à importer
data "coder_parameter" "git_repository" {
  name        = "📂 Dépôt Git à cloner"
  description = "URL du dépôt Git à cloner dans votre espace de travail"
  type        = "string"
  default     = ""
  order       = 1
  mutable     = true
  icon        = "/icon/git.svg"
  
  validation {
    regex = "^(|https?://|git@).*"
    error = "Git doit être une URL valide commençant par http://, https:// ou git@, ou être vide"
  }
}

# 2. Choix du mode d'environnement (devcontainer ou prédéfini)
data "coder_parameter" "use_devcontainer" {
  name        = "🛠️ Utiliser la configuration DevContainer"
  description = "Si le dépôt contient un fichier devcontainer.json, l'utiliser pour configurer l'environnement"
  type        = "bool"
  default     = "false"
  mutable     = true
  order       = 2
  icon        = "/icon/docker.svg"
}

# 3. Options pour l'environnement standard (utilisé seulement si devcontainer = false)
data "coder_parameter" "docker_image" {
  name        = "🐳 Image de développement"
  description = "Choisissez l'environnement de développement adapté à votre projet. (Uniquement applicable si 'Utiliser la configuration DevContainer' = Non)"
  type        = "string"
  default     = "base"
  mutable     = true
  order       = 3

  option {
    name  = "JavaScript"
    value = "javascript"
    icon  = "/icon/javascript.svg"
  }

  option {
    name  = "TypeScript"
    value = "typescript"
    icon  = "/icon/typescript.svg"
  }

  option {
    name  = "PHP"
    value = "php"
    icon  = "/icon/php.svg"
  }

  option {
    name  = "Java"
    value = "java"
    icon  = "/icon/java.svg"
  }

  option {
    name  = "Python"
    value = "python"
    icon  = "/icon/python.svg"
  }

  option {
    name  = "Dart"
    value = "dart"
    icon  = "/icon/dart.svg"
  }

  option {
    name  = "Base (Environnement générique)"
    value = "base"
    icon  = "/icon/terminal.svg"
  }
}

# 4. Options pour le devcontainer
data "coder_parameter" "fallback_image" {
  name        = "🔄 Image de secours"
  description = "Cette image sera utilisée si la construction du devcontainer échoue. (Uniquement applicable si 'Utiliser la configuration DevContainer' = Oui)"
  type        = "string"
  mutable     = true
  order       = 4
  icon        = "/icon/docker.svg"
  
  # Utilise l'image de base comme valeur par défaut
  default     = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/base:latest"

  # Options prédéfinies pour faciliter la sélection
  option {
    name  = "JavaScript"
    value = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/javascript:latest"
  }
  
  option {
    name  = "TypeScript"
    value = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/typescript:latest"
  }
  
  option {
    name  = "PHP"
    value = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/php:latest"
  }
  
  option {
    name  = "Java"
    value = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/java:latest"
  }
  
  option {
    name  = "Python"
    value = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/python:latest"
  }
  
  option {
    name  = "Dart"
    value = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/dart:latest"
  }
  
  option {
    name  = "Base"
    value = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/base:latest"
  }
}

data "coder_parameter" "devcontainer_builder" {
  name        = "🏗️ Image de construction"
  description = "Image qui construira le devcontainer. (Uniquement applicable si 'Utiliser la configuration DevContainer' = Oui)"
  mutable     = true
  default     = "ghcr.io/coder/envbuilder:latest"
  order       = 5
  icon        = "/icon/docker.svg"
  
  # Options pour différentes versions
  option {
    name  = "Latest"
    value = "ghcr.io/coder/envbuilder:latest"
  }
  
  option {
    name  = "v0.3.10"
    value = "ghcr.io/coder/envbuilder:v0.3.10"
  }
}

# 5. Options d'interface utilisateur
data "coder_parameter" "vnc" {
  name        = "🖥️ Interface graphique (VNC)"
  description = "Activer une interface bureau à distance via noVNC"
  type        = "bool"
  default     = "true"
  order       = 7
  mutable     = true
  icon        = "/icon/novnc.svg"
}

# 6. Options de personnalisation
data "coder_parameter" "shell" {
  name        = "🐚 Shell par défaut"
  description = "Choisissez votre shell préféré"
  type        = "string"
  default     = "bash"
  order       = 8
  mutable     = true
  icon        = "/icon/terminal.svg"

  option {
    name  = "Bash"
    value = "bash"
    icon  = "/icon/bash.svg"
  }
  
  option {
    name  = "ZSH"
    value = "zsh"
    icon  = "/icon/zsh.svg"
  }

  option {
    name  = "Sh"
    value = "sh"
    icon  = "/icon/shell.svg"
  }
}

data "coder_parameter" "vscode_binary" {
  name        = "💻 Version VS Code"
  description = "Choisissez entre la version stable ou Insiders de VS Code"
  type        = "string"
  default     = "code"
  order       = 9
  mutable     = true
  icon        = "/icon/vscode.svg"

  option {
    name  = "Stable"
    value = "code"
    icon  = "/icon/vscode.svg"
  }

  option {
    name  = "Insiders"
    value = "code-insiders"
    icon  = "/icon/vscode-insiders.svg"
  }
}

# 7. Options pour les extensions VS Code
data "coder_parameter" "vscode_extensions_git" {
  name        = "🔄 Extensions Git"
  description = "Activer les extensions Git pour VS Code"
  type        = "bool"
  default     = "true"
  order       = 10
  mutable     = true
  icon        = "/icon/git.svg"
}

data "coder_parameter" "vscode_extensions_github_copilot" {
  name        = "🤖 Extensions GitHub Copilot"
  description = "Activer les extensions GitHub Copilot pour VS Code"
  type        = "bool"
  default     = "true"
  order       = 11
  mutable     = true
  icon        = "/icon/github.svg"
}

data "coder_parameter" "vscode_extensions_languages" {
  name        = "📝 Extensions de Langages"
  description = "Activer les extensions de langages pour VS Code"
  type        = "bool"
  default     = "true"
  order       = 12
  mutable     = true
  icon        = "/icon/code.svg"
}

data "coder_parameter" "vscode_extensions_productivity" {
  name        = "⚡ Extensions de Productivité"
  description = "Activer les extensions de productivité pour VS Code"
  type        = "bool"
  default     = "true"
  order       = 13
  mutable     = true
  icon        = "/icon/productivity.svg"
}

data "coder_parameter" "vscode_extensions_viewers" {
  name        = "👁️ Extensions de Visionneuses"
  description = "Activer les extensions de visionneuses pour VS Code"
  type        = "bool"
  default     = "true"
  order       = 14
  mutable     = true
  icon        = "/icon/preview.svg"
}

data "coder_parameter" "vscode_extensions_collaboration" {
  name        = "👥 Extensions de Collaboration"
  description = "Activer les extensions de collaboration pour VS Code"
  type        = "bool"
  default     = "true"
  order       = 15
  mutable     = true
  icon        = "/icon/collaboration.svg"
}

data "coder_parameter" "vscode_extensions_intelligence" {
  name        = "🧠 Extensions d'Intelligence"
  description = "Activer les extensions d'intelligence pour VS Code"
  type        = "bool"
  default     = "true"
  order       = 16
  mutable     = true
  icon        = "/icon/intellicode.svg"
}

data "coder_parameter" "vscode_extensions_server" {
  name        = "🌐 Extensions de Serveur"
  description = "Activer les extensions de serveur pour VS Code"
  type        = "bool"
  default     = "true"
  order       = 17
  mutable     = true
  icon        = "/icon/server.svg"
}

resource "docker_container" "workspace" {
  # On ne crée le conteneur standard que si on n'utilise pas devcontainer
  count = data.coder_workspace.me.start_count > 0 && !local.use_devcontainer ? 1 : 0

  # we need to define a relation table in locals because we can't simply access resources like this: docker_image["javascript"]
  # we need to access [0] because we define a count in the docker_image's definition
  image = local.images[data.coder_parameter.docker_image.value][0].image_id

  # Use privileged mode instead of sysbox-runc for Docker-in-Docker functionality
  privileged = true
  
  name     = local.container_name
  hostname = local.workspace_name

  # Configuration DNS améliorée pour une meilleure résolution des noms d'hôtes
  dns = local.dns_servers

  entrypoint = ["sh", "-c", replace(coder_agent.dev.init_script, "127.0.0.1", "host.docker.internal")]
  env        = [
    "CODER_AGENT_TOKEN=${coder_agent.dev.token}",
    "GIT_HTTP_TIMEOUT=${local.git_timeout_seconds}",
    "GIT_DISCOVERY_ACROSS_FILESYSTEM=1"
  ]

  volumes { 
    volume_name    = docker_volume.home.name
    container_path = "/home/coder/"
    read_only      = false
  }

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  # Support des IPv6 pour une meilleure connectivité réseau
  network_mode = "bridge"

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = local.user_name
  }

  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }

  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}

# Création d'un conteneur Docker pour le devcontainer
resource "docker_container" "devcontainer" {
  count = local.use_devcontainer ? data.coder_workspace.me.start_count : 0

  # Utiliser l'image en cache si disponible, sinon utiliser l'image de secours
  image = (var.cache_repo != "") ? "${var.cache_repo}/${local.container_name}:latest" : data.coder_parameter.fallback_image.value
  
  name     = local.container_name
  hostname = local.workspace_name
  
  # Active le mode privilégié pour permettre Docker-in-Docker
  privileged = true
  
  # Amélioration de la gestion des timeouts et des options réseau
  network_mode = "bridge"
  restart = "on-failure"
  
  # Configuration du script d'initialisation et du token d'agent
  entrypoint = ["sh", "-c", replace(coder_agent.dev.init_script, "127.0.0.1", "host.docker.internal")]
  env        = concat(
    [
      "CODER_AGENT_TOKEN=${coder_agent.dev.token}",
      "GIT_HTTP_TIMEOUT=${local.git_timeout_seconds}",
      "GIT_DISCOVERY_ACROSS_FILESYSTEM=1",
      "DEVCONTAINER_GITHUB_URL=${data.coder_parameter.git_repository.value}", # Utilisation du paramètre commun git_repository
      "BUILD_START_TIME=${timestamp()}" # Pour suivre le temps de construction
    ],
    local.docker_env
  )
  
  # Montage du volume home
  volumes { 
    volume_name    = docker_volume.home.name
    container_path = "/home/coder/"
    read_only      = false
  }
  
  # Montage du socket Docker pour Docker-in-Docker plus rapide
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = false
  }
  
  # Montage d'un volume pour le cache Docker pour accélérer les builds
  volumes {
    container_path = "/var/lib/docker"
    volume_name    = "${local.container_name}-docker-cache"
    read_only      = false
  }
  
  # Accès à l'hôte Docker pour Docker-in-Docker
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  
  # Configuration DNS optimisée
  dns = local.dns_servers
  
  # Étiquettes pour le suivi des ressources
  labels {
    label = "coder.owner"
    value = local.user_name
  }
  
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  
  labels {
    label = "devcontainer.repository_url"
    value = data.coder_parameter.git_repository.value
  }
}

module "vscode-web" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/modules/vscode-web/coder"
  auto_install_extensions = true
  agent_id       = coder_agent.dev.id
  accept_license = true
  folder = "~/projects"
  subdomain = false
  use_cached = true
  extensions = local.selected_extensions
}

module "github-upload-public-key" {
  count            = local.github_auth_enabled && data.coder_workspace.me.start_count > 0 ? data.coder_workspace.me.start_count : 0
  source           = "registry.coder.com/modules/github-upload-public-key/coder"

  agent_id         = coder_agent.dev.id
  external_auth_id = local.github_auth_enabled ? "myauthid" : ""
}

module "dotfiles" {
  source   = "registry.coder.com/modules/dotfiles/coder"

  coder_parameter_order = 5

  agent_id = coder_agent.dev.id
}

module "dotfiles-root" {
  source       = "registry.coder.com/modules/dotfiles/coder"

  user         = "root"
  dotfiles_uri = module.dotfiles.dotfiles_uri

  agent_id     = coder_agent.dev.id
}

module "git-config" {
  source = "registry.coder.com/modules/git-config/coder"
  
  allow_username_change = true
  allow_email_change = true
  
  agent_id = coder_agent.dev.id
}

module "cursor" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/cursor/coder"
  version  = "1.0.19"
  agent_id = coder_agent.dev.id
  folder   = "/home/coder/projects"
}

module "git-clone" {
  # Ne clonez pas automatiquement le repo Coder si un autre repo est spécifié ou si on est en mode devcontainer
  count    = (data.coder_parameter.git_repository.value == "" && !local.use_devcontainer) ? 0 : 0
  source   = "registry.coder.com/modules/git-clone/coder"

  agent_id = coder_agent.dev.id
  url      = "https://github.com/coder/coder"
  base_dir = "~/projects"
}

module "coder-login" {
  source   = "registry.coder.com/modules/coder-login/coder"
  
  agent_id = coder_agent.dev.id
}

module "personalize" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/personalize/coder"
  agent_id = coder_agent.dev.id
}

module "filebrowser" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/filebrowser/coder"
  agent_id = coder_agent.dev.id
  folder   = "~/projects"
  subdomain  = false
}

module "git-commit-signing" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/git-commit-signing/coder"
  agent_id = coder_agent.dev.id
}

resource "coder_app" "novnc" {
  count    = data.coder_parameter.vnc.value == "true" ? 1 : 0
  agent_id = coder_agent.dev.id

  display_name = "noVNC"
  slug         = "novnc"

  order = 1

  # Mise à jour de la configuration pour correspondre à celle intégrée dans les images
  url  = "http://localhost:6080"
  icon = "/icon/novnc.svg"

  subdomain = local.enable_subdomains
}

# La ressource coder_app "supervisor" est supprimée car les statistiques sont maintenant intégrées dans l'agent

resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.id}-home"

  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = local.user_name
  }

  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }

  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}

resource "coder_metadata" "home" {
  resource_id = docker_volume.home.id

  hide = true

  item {
    key = "description"
    value = "Home volume"
  }
}

data "docker_registry_image" "javascript" {
  count = data.coder_parameter.docker_image.value == "javascript" ? 1 : 0

  name = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/javascript:latest"
}

resource "docker_image" "javascript" {
  count = data.coder_parameter.docker_image.value == "javascript" ? 1 : 0

  name          = data.docker_registry_image.javascript[0].name
  pull_triggers = [data.docker_registry_image.javascript[0].sha256_digest]
  
  # Amélioration de la vitesse de téléchargement
  keep_locally = true
}

data "docker_registry_image" "typescript" {
  count = data.coder_parameter.docker_image.value == "typescript" ? 1 : 0

  name = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/typescript:latest"
}

resource "docker_image" "typescript" {
  count = data.coder_parameter.docker_image.value == "typescript" ? 1 : 0

  name          = data.docker_registry_image.typescript[0].name
  pull_triggers = [data.docker_registry_image.typescript[0].sha256_digest]
  
  # Optimisations pour accélérer le téléchargement et le build
  keep_locally = true
}

data "docker_registry_image" "php" {
  count = data.coder_parameter.docker_image.value == "php" ? 1 : 0

  name = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/php:latest"
}

resource "docker_image" "php" {
  count = data.coder_parameter.docker_image.value == "php" ? 1 : 0

  name          = data.docker_registry_image.php[0].name
  pull_triggers = [data.docker_registry_image.php[0].sha256_digest]
  
  # Optimisations pour accélérer le téléchargement et le build
  keep_locally = true
}

data "docker_registry_image" "java" {
  count = data.coder_parameter.docker_image.value == "java" ? 1 : 0

  name = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/java:latest"
}

resource "docker_image" "java" {
  count = data.coder_parameter.docker_image.value == "java" ? 1 : 0

  name          = data.docker_registry_image.java[0].name
  pull_triggers = [data.docker_registry_image.java[0].sha256_digest]
  
  # Optimisations pour accélérer le téléchargement et le build
  keep_locally = true
}

data "docker_registry_image" "python" {
  count = data.coder_parameter.docker_image.value == "python" ? 1 : 0

  name = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/python:latest"
}

resource "docker_image" "python" {
  count = data.coder_parameter.docker_image.value == "python" ? 1 : 0

  name          = data.docker_registry_image.python[0].name
  pull_triggers = [data.docker_registry_image.python[0].sha256_digest]
  
  # Optimisations pour accélérer le téléchargement et le build
  keep_locally = true
}

data "docker_registry_image" "dart" {
  count = data.coder_parameter.docker_image.value == "dart" ? 1 : 0
  name = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/dart:latest"
}

resource "docker_image" "dart" {
  count = data.coder_parameter.docker_image.value == "dart" ? 1 : 0

  name          = data.docker_registry_image.dart[0].name
  pull_triggers = [data.docker_registry_image.dart[0].sha256_digest]
  
  # Optimisations pour accélérer le téléchargement et le build
  keep_locally = true
}

data "docker_registry_image" "base" {
  count = data.coder_parameter.docker_image.value == "base" ? 1 : 0

  name = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/base:latest"
}

resource "docker_image" "base" {
  count = data.coder_parameter.docker_image.value == "base" ? 1 : 0

  name          = data.docker_registry_image.base[0].name
  pull_triggers = [data.docker_registry_image.base[0].sha256_digest]
  
  # Optimisations pour accélérer le téléchargement et le build
  keep_locally = true
}

resource "docker_image" "devcontainer_builder_image" {
  count        = local.use_devcontainer ? 1 : 0
  name         = data.coder_parameter.devcontainer_builder.value
  keep_locally = true
}

resource "coder_metadata" "javascript_image" {
  count = data.coder_parameter.docker_image.value == "javascript" ? 1 : 0

  resource_id = docker_image.javascript[0].id

  hide = true

  item {
    key   = "description"
    value = "JavaScript container image"
  }
}

resource "coder_metadata" "typescript_image" {
  count = data.coder_parameter.docker_image.value == "typescript" ? 1 : 0

  resource_id = docker_image.typescript[0].id

  hide = true

  item {
    key   = "description"
    value = "TypeScript container image"
  }
}

resource "coder_metadata" "php_image" {
  count = data.coder_parameter.docker_image.value == "php" ? 1 : 0

  resource_id = docker_image.php[0].id

  hide = true

  item {
    key   = "description"
    value = "PHP container image"
  }
}

resource "coder_metadata" "java_image" {
  count = data.coder_parameter.docker_image.value == "java" ? 1 : 0

  resource_id = docker_image.java[0].id

  hide = true

  item {
    key   = "description"
    value = "Java container image"
  }
}

resource "coder_metadata" "python_image" {
  count = data.coder_parameter.docker_image.value == "python" ? 1 : 0

  resource_id = docker_image.python[0].id

  hide = true

  item {
    key   = "description"
    value = "Python container image"
  }
}

resource "coder_metadata" "dart_image" {
  count = data.coder_parameter.docker_image.value == "dart" ? 1 : 0

  resource_id = docker_image.dart[0].id

  hide = true

  item {
    key   = "description"
    value = "Dart container image"
  }
}

resource "coder_metadata" "base_image" {
  count = data.coder_parameter.docker_image.value == "base" ? 1 : 0

  resource_id = docker_image.base[0].id

  hide = true

  item {
    key   = "description"
    value = "Base container image"
  }
}

# Cache repo config for Docker 
data "local_sensitive_file" "cache_repo_dockerconfigjson" {
  count    = var.cache_repo_docker_config_path == "" ? 0 : 1
  filename = var.cache_repo_docker_config_path
}

resource "coder_metadata" "extensions" {
  count = data.coder_workspace.me.start_count
  resource_id = module.vscode-web[0].id
  icon = "/icon/vscode.svg"
  order = 2
  
  item {
    key   = "🔄 Extensions Git"
    value = data.coder_parameter.vscode_extensions_git.value == "true" ? "Activées" : "Désactivées"
  }
  
  item {
    key   = "🤖 Extensions GitHub Copilot"
    value = data.coder_parameter.vscode_extensions_github_copilot.value == "true" ? "Activées" : "Désactivées"
  }
  
  item {
    key   = "📝 Extensions de Langages"
    value = data.coder_parameter.vscode_extensions_languages.value == "true" ? "Activées" : "Désactivées"
  }
  
  item {
    key   = "⚡ Extensions de Productivité"
    value = data.coder_parameter.vscode_extensions_productivity.value == "true" ? "Activées" : "Désactivées"
  }
  
  item {
    key   = "👁️ Extensions de Visionneuses"
    value = data.coder_parameter.vscode_extensions_viewers.value == "true" ? "Activées" : "Désactivées"
  }
  
  item {
    key   = "👥 Extensions de Collaboration"
    value = data.coder_parameter.vscode_extensions_collaboration.value == "true" ? "Activées" : "Désactivées"
  }
  
  item {
    key   = "🧠 Extensions d'Intelligence"
    value = data.coder_parameter.vscode_extensions_intelligence.value == "true" ? "Activées" : "Désactivées"
  }
  
  item {
    key   = "🌐 Extensions de Serveur"
    value = data.coder_parameter.vscode_extensions_server.value == "true" ? "Activées" : "Désactivées"
  }
  
  item {
    key   = "📊 Nombre total d'extensions"
    value = length(local.selected_extensions)
  }
}

# Ajout de métadonnées détaillées pour les extensions installées
resource "coder_metadata" "extensions_detail" {
  count = data.coder_workspace.me.start_count
  resource_id = module.vscode-web[0].id
  icon = "/icon/extension.svg"
  order = 3
  hide = true
  
  dynamic "item" {
    for_each = data.coder_parameter.vscode_extensions_git.value == "true" ? local.vscode_extensions.git : []
    content {
      key   = "Git: ${split(".", item.value)[1]}"
      value = item.value
    }
  }
  
  dynamic "item" {
    for_each = data.coder_parameter.vscode_extensions_github_copilot.value == "true" ? local.vscode_extensions.github_copilot : []
    content {
      key   = "GitHub Copilot: ${split(".", item.value)[1]}"
      value = item.value
    }
  }
  
  dynamic "item" {
    for_each = data.coder_parameter.vscode_extensions_languages.value == "true" ? local.vscode_extensions.languages : []
    content {
      key   = "Langage: ${split(".", item.value)[1]}"
      value = item.value
    }
  }
  
  dynamic "item" {
    for_each = data.coder_parameter.vscode_extensions_productivity.value == "true" ? local.vscode_extensions.productivity : []
    content {
      key   = "Productivité: ${split(".", item.value)[1]}"
      value = item.value
    }
  }
  
  dynamic "item" {
    for_each = data.coder_parameter.vscode_extensions_viewers.value == "true" ? local.vscode_extensions.viewers : []
    content {
      key   = "Visionneuse: ${split(".", item.value)[1]}"
      value = item.value
    }
  }
  
  dynamic "item" {
    for_each = data.coder_parameter.vscode_extensions_collaboration.value == "true" ? local.vscode_extensions.collaboration : []
    content {
      key   = "Collaboration: ${split(".", item.value)[1]}"
      value = item.value
    }
  }
  
  dynamic "item" {
    for_each = data.coder_parameter.vscode_extensions_intelligence.value == "true" ? local.vscode_extensions.intelligence : []
    content {
      key   = "Intelligence: ${split(".", item.value)[1]}"
      value = item.value
    }
  }
  
  dynamic "item" {
    for_each = data.coder_parameter.vscode_extensions_server.value == "true" ? local.vscode_extensions.server : []
    content {
      key   = "Serveur: ${split(".", item.value)[1]}"
      value = item.value
    }
  }
}