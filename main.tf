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
    base = docker_image.base
  }
  
  # Flag to control GitHub integration
  github_auth_enabled = false
  
  # Owner related attributes to replace deprecated ones
  owner_name = data.coder_workspace_owner.me.name
  owner_email = data.coder_workspace_owner.me.email
  owner_session_token = data.coder_workspace_owner.me.session_token
  
  # Indiquer si l'utilisateur a choisi d'utiliser un devcontainer
  use_devcontainer = data.coder_parameter.environment_type.value == "devcontainer"
  
  # EnvBuilder configuration
  container_name = "coder-${local.user_name}-${local.workspace_name}"
  devcontainer_builder_image = data.coder_parameter.devcontainer_builder.value
  git_author_name = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
  repo_url = local.use_devcontainer ? data.coder_parameter.repo_url.value : ""
  
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
  }
  
  # Calculer l'image de secours en fonction des choix utilisateur
  fallback_image = local.use_devcontainer ? data.coder_parameter.fallback_image.value : null

  # Convert the environment variables map to the format expected by the docker provider
  docker_env = [
    for k, v in local.envbuilder_env : "${k}=${v}"
  ]
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
  }

  startup_script = <<EOT
#!/bin/bash
echo "[+] Setting default shell"
SHELL=$(which $SHELL)
sudo chsh -s $SHELL $USER
sudo chsh -s $SHELL root

echo "[+] Starting code-server"
code-server --auth none --port 13337 >/dev/null 2>&1 &

# Clone Git repository if URL is provided
if [ ! -z "$GIT_REPO" ]; then
  echo "[+] Cloning Git repository: $GIT_REPO"
  cd ~/projects
  
  # Extract repo name from URL
  REPO_NAME=$(basename "$GIT_REPO" .git)
  
  # Check if directory already exists
  if [ -d "$REPO_NAME" ]; then
    echo "[*] Repository directory already exists, updating instead"
    cd "$REPO_NAME"
    git pull
  else
    git clone "$GIT_REPO"
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
# 1. Choix du type d'environnement (standard ou devcontainer)
data "coder_parameter" "environment_type" {
  name        = "Type d'environnement"
  description = "Choisissez entre un environnement prédéfini ou une configuration personnalisée via devcontainer"
  type        = "string"
  default     = "standard"
  mutable     = true
  order       = 1
  
  option {
    name  = "Environnement prédéfini"
    value = "standard"
    icon  = "/icon/terminal.svg"
  }
  
  option {
    name  = "DevContainer personnalisé"
    value = "devcontainer"
    icon  = "/icon/docker.svg"
  }
}

# 2. Options pour l'environnement standard
data "coder_parameter" "docker_image" {
  name        = "Image de développement"
  description = "Choisissez l'environnement de développement adapté à votre projet. ${data.coder_parameter.environment_type.value != "standard" ? "(Uniquement applicable si 'Environnement prédéfini' est sélectionné)" : ""}"
  type        = "string"
  default     = "base"
  mutable     = true
  order       = 2

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
    name  = "Base (Environnement générique)"
    value = "base"
    icon  = "/icon/terminal.svg"
  }
}

# 3. Options pour l'environnement DevContainer
data "coder_parameter" "repo_url" {
  name        = "URL du dépôt avec devcontainer"
  description = "URL du dépôt Git contenant une configuration devcontainer.json. ${data.coder_parameter.environment_type.value != "devcontainer" ? "(Uniquement applicable si 'DevContainer personnalisé' est sélectionné)" : ""}"
  type        = "string"
  mutable     = true
  default     = ""
  order       = 3

  validation {
    regex = "^(|https?://|git@).*"
    error = "Doit être une URL Git valide commençant par http://, https:// ou git@"
  }
}

data "coder_parameter" "fallback_image" {
  name        = "Image de secours"
  description = "Cette image sera utilisée si la construction du devcontainer échoue. ${data.coder_parameter.environment_type.value != "devcontainer" ? "(Uniquement applicable si 'DevContainer personnalisé' est sélectionné)" : ""}"
  type        = "string"
  mutable     = true
  order       = 4
  
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
    name  = "Base"
    value = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/base:latest"
  }
}

data "coder_parameter" "devcontainer_builder" {
  name        = "Image de construction"
  description = "Image qui construira le devcontainer (recommandation: utilisez une version spécifique). ${data.coder_parameter.environment_type.value != "devcontainer" ? "(Uniquement applicable si 'DevContainer personnalisé' est sélectionné)" : ""}"
  mutable     = true
  default     = "ghcr.io/coder/envbuilder:latest"
  order       = 5
  
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

# 4. Options communes - Git
data "coder_parameter" "git_repository" {
  name        = "Dépôt Git à cloner"
  description = "URL d'un dépôt Git à cloner automatiquement (différent du dépôt DevContainer)"
  type        = "string"
  default     = ""
  order       = 6
  mutable     = true
  
  validation {
    regex = "^(|https?://|git@).*"
    error = "Git doit être une URL valide commençant par http://, https:// ou git@, ou être vide"
  }
}

# 5. Options d'interface utilisateur
data "coder_parameter" "vnc" {
  name        = "Interface graphique (VNC)"
  description = "Activer une interface bureau à distance via noVNC"
  type        = "bool"
  default     = "true"
  order       = 7
  mutable     = true
  icon        = "/icon/novnc.svg"
}

# 6. Options de personnalisation
data "coder_parameter" "shell" {
  name        = "Shell par défaut"
  description = "Choisissez votre shell préféré"
  type        = "string"
  default     = "bash"
  order       = 8
  mutable     = true

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
  name        = "Version VS Code"
  description = "Choisissez entre la version stable ou Insiders de VS Code"
  type        = "string"
  default     = "code"
  order       = 9
  mutable     = true

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

  dns      = [
    "100.100.100.100",
    "1.1.1.1"
    ]

  entrypoint = ["sh", "-c", replace(coder_agent.dev.init_script, "127.0.0.1", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.dev.token}"]

  volumes { 
    volume_name    = docker_volume.home.name
    container_path = "/home/coder/"
    read_only      = false
  }

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
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

# Création d'un conteneur Docker pour le devcontainer
resource "docker_container" "devcontainer" {
  count = local.use_devcontainer ? data.coder_workspace.me.start_count : 0

  # Correction de la syntaxe de l'expression conditionnelle
  image = (var.cache_repo != "") ? "${var.cache_repo}/${local.container_name}:latest" : data.coder_parameter.fallback_image.value
  
  name     = local.container_name
  hostname = local.workspace_name
  
  # Active le mode privilégié pour permettre Docker-in-Docker
  privileged = true
  
  # Configuration du script d'initialisation et du token d'agent
  entrypoint = ["sh", "-c", replace(coder_agent.dev.init_script, "127.0.0.1", "host.docker.internal")]
  env        = concat(
    ["CODER_AGENT_TOKEN=${coder_agent.dev.token}"],
    local.docker_env
  )
  
  # Montage du volume home
  volumes { 
    volume_name    = docker_volume.home.name
    container_path = "/home/coder/"
    read_only      = false
  }
  
  # Accès à l'hôte Docker pour Docker-in-Docker
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  
  # Configuration DNS
  dns = [
    "100.100.100.100",
    "1.1.1.1"
  ]
  
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
  extensions = [
    "mads-hartmann.bash-ide-vscode",
    "mikestead.dotenv",
    "vivaxy.vscode-conventional-commits",
    "ms-azuretools.vscode-docker",
    "EditorConfig.EditorConfig",
    "PeterSchmalfeldt.explorer-exclude",
    "mhutchie.git-graph",
    "donjayamanne.githistory",
    "shyykoserhiy.git-autoconfig",
    "github.vscode-github-actions",
    "GitHub.copilot",
    "GitHub.copilot-chat",
    "GitHub.vscode-pull-request-github",
    "ms-vscode.live-server",
    "spmeesseman.vscode-taskexplorer",
    "tilt-dev.tiltfile",
    "jock.svg",
    "Gruntfuggly.todo-tree",
    "shardulm94.trailing-spaces",
    "XuangeAha.vsmarketplace-badges",
    "redhat.vscode-yaml",
    "aaron-bond.better-comments",
    "GitHub.remotehub",
    "ms-vscode.remote-repositories",
    "usernamehw.errorlens",
    "formulahendry.auto-rename-tag",
    "cweijan.dbclient-jdbc",
    "ms-vscode-remote.vscode-remote-extensionpack",
    "VisualStudioExptTeam.vscodeintellicode",
    "VisualStudioExptTeam.intellicode-api-usage-examples",
    "eliostruyf.vscode-front-matter-beta",
    "oderwat.indent-rainbow",
    "DavidAnson.vscode-markdownlint",
    "ms-edgedevtools.vscode-edge-devtools",
    "formulahendry.code-runner",
    "ms-windows-ai-studio.windows-ai-studio",
    "IBM.output-colorizer",
    "EverlastEngineering.debug-in-titlebar",
    "DutchIgor.json-viewer",
    "elagil.pre-commit-helper",
    "ms-vscode.vscode-websearchforcopilot",
    "GitHub.copilot-workspace",
    "ms-azuretools.vscode-azure-github-copilot",
    "ms-vscode.vscode-copilot-vision",
    "ms-vscode.vscode-copilot-data-analysis",
    "bierner.markdown-preview-github-styles",
    "berublan.vscode-log-viewer",
    "christian-kohler.path-intellisense",
    "ms-vsliveshare.vsliveshare",
    "bierner.github-markdown-preview",
    "JeronimoEkerdt.color-picker-universal",
    "howardzuo.vscode-git-tags",
    "qcz.text-power-tools",
    "timonwong.shellcheck",
    "antfu.iconify",
    "GrapeCity.gc-excelviewer",
    "foxundermoon.shell-format",
    "mindaro-dev.file-downloader",
    "AutomataLabs.copilot-mcp",
    "maciejdems.add-to-gitignore",
    "vscode-icons-team.vscode-icons",
    "ms-vscode.vscode-speech",
    "wayou.vscode-todo-highlight",
    "tomoki1207.pdf",
    "adamraichu.docx-viewer",
    "RandomFractalsInc.geo-data-viewer",
    "VisualStudioExptTeam.vscodeintellicode-completions",
    "moalamri.inline-fold",
    "ritwickdey.LiveServer",
    "BeardedBear.beardedtheme",
    "genaiscript.genaiscript-vscode",
    "ms-toolsai.prompty",
    "prompt-flow.prompt-flow",
    "ms-vscode.vscode-commander",
    "adautomendes.yaml2table-preview"
  ]
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
  count    = data.coder_workspace.me.start_count
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
}

data "docker_registry_image" "typescript" {
  count = data.coder_parameter.docker_image.value == "typescript" ? 1 : 0

  name = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/typescript:latest"
}

resource "docker_image" "typescript" {
  count = data.coder_parameter.docker_image.value == "typescript" ? 1 : 0

  name          = data.docker_registry_image.typescript[0].name
  pull_triggers = [data.docker_registry_image.typescript[0].sha256_digest]
}

data "docker_registry_image" "php" {
  count = data.coder_parameter.docker_image.value == "php" ? 1 : 0

  name = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/php:latest"
}

resource "docker_image" "php" {
  count = data.coder_parameter.docker_image.value == "php" ? 1 : 0

  name          = data.docker_registry_image.php[0].name
  pull_triggers = [data.docker_registry_image.php[0].sha256_digest]
}

data "docker_registry_image" "java" {
  count = data.coder_parameter.docker_image.value == "java" ? 1 : 0

  name = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/java:latest"
}

resource "docker_image" "java" {
  count = data.coder_parameter.docker_image.value == "java" ? 1 : 0

  name          = data.docker_registry_image.java[0].name
  pull_triggers = [data.docker_registry_image.java[0].sha256_digest]
}

data "docker_registry_image" "python" {
  count = data.coder_parameter.docker_image.value == "python" ? 1 : 0

  name = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/python:latest"
}

resource "docker_image" "python" {
  count = data.coder_parameter.docker_image.value == "python" ? 1 : 0

  name          = data.docker_registry_image.python[0].name
  pull_triggers = [data.docker_registry_image.python[0].sha256_digest]
}

data "docker_registry_image" "base" {
  count = data.coder_parameter.docker_image.value == "base" ? 1 : 0

  name = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/base:latest"
}

resource "docker_image" "base" {
  count = data.coder_parameter.docker_image.value == "base" ? 1 : 0

  name          = data.docker_registry_image.base[0].name
  pull_triggers = [data.docker_registry_image.base[0].sha256_digest]
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