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
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

provider "coder" {}

provider "envbuilder" {}

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
    "VNC_ENABLED"   = data.coder_parameter.vnc.value,
    "SHELL"         = data.coder_parameter.shell.value,
    "VSCODE_BINARY" = data.coder_parameter.vscode_binary.value,
    "SUPERVISOR_DIR" = "/usr/share/basic-env/supervisor",
    "GIT_REPO"      = data.coder_parameter.git_repository.value,
    "CODER_USER_TOKEN" = local.owner_session_token,
    "GIT_USERNAME" = local.owner_name,
    "GIT_EMAIL" = local.owner_email
  }

  startup_script = <<EOT
#!/bin/bash
echo "[+] Setting default shell"
SHELL=$(which $SHELL)
sudo chsh -s $SHELL $USER
sudo chsh -s $SHELL root

# Start supervisord
supervisord

echo "[+] Starting code-server"
supervisorctl start code-server

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
  # Generate VNC password file
  VNC_PWD='${data.coder_parameter.vnc.value == "true" ? random_string.vnc_password[0].result : ""}'
  echo "$VNC_PWD" | tightvncpasswd -f > $HOME/.vnc/passwd
  supervisorctl start vnc:*
fi
EOT
}

data "coder_parameter" "docker_image" {
  name        = "Docker Image"
  description = "Quelle image ?"

  type    = "string"
  default = "base"

  order = 1

  mutable = true

  option {
    name  = "JavaScript"
    value = "javascript"
  }

  option {
    name  = "Typescript"
    value = "typescript"
  }

  option {
    name  = "PHP"
    value = "php"
  }

  option {
    name  = "Java"
    value = "java"
  }

  option {
    name  = "Python"
    value = "python"
  }


  option {
    name  = "Base"
    value = "base"
  }
}

data "coder_parameter" "shell" {
  name        = "Shell"
  description = "Quel shell par défaut ?"

  type    = "string"
  default = "bash"

  order = 2

  mutable = true

  option {
    name  = "Bash"
    value = "bash"
  }
  
  option {
    name  = "ZSH"
    value = "zsh"
  }

  option {
    name  = "sh"
    value = "sh"
  }
}

data "coder_parameter" "vnc" {
  name        = "VNC"
  description = "Activer VNC?"

  order = 3

  type    = "bool"
  default = "true"

  mutable = true
}

data "coder_parameter" "vscode_binary" {
  name        = "VS Code Channel"
  description = "Quelle version de VS Code ?"

  type    = "string"
  default = "code"

  order = 4

  mutable = true

  option {
    name  = "Stable"
    value = "code"
  }

  option {
    name  = "Insiders"
    value = "code-insiders"
  }
}

data "coder_parameter" "git_repository" {
  name        = "Git Repository"
  description = "URL du dépôt Git à cloner"
  type        = "string"
  default     = ""
  order       = 5
  mutable     = true

  validation {
    regex = "^(|https?://|git@).*"
    error = "Git doit être une URL valide commençant par http://, https:// ou git@, ou être vide"
  }
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

  agent_id = coder_agent.dev.id
  folder   = "/workspaces"
}

module "git-clone" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/git-clone/coder"

  agent_id = coder_agent.dev.id
  url      = "https://github.com/coder/coder"
  base_dir = "/workspaces"
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
}

module "git-commit-signing" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/git-commit-signing/coder"
  agent_id = coder_agent.dev.id
}

resource "coder_app" "code-server" {
  agent_id = coder_agent.dev.id

  display_name = "VS Code Web"
  slug         = "code-server"

  order = 1

  url  = "http://localhost:8000/?folder=/home/coder/projects"
  icon = "/icon/code.svg"

  subdomain = local.enable_subdomains
}

resource "coder_app" "novnc" {
  count    = data.coder_parameter.vnc.value == "true" ? 1 : 0
  agent_id = coder_agent.dev.id

  display_name = "noVNC"
  slug         = "novnc"

  order = 2

  url  = "http://localhost:8081?autoconnect=1&resize=scale&path=@${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}.dev/apps/noVNC/websockify&password=${random_string.vnc_password[0].result}"
  icon = "/icon/novnc.svg"

  subdomain = local.enable_subdomains
}

resource "coder_app" "supervisor" {
  agent_id = coder_agent.dev.id

  display_name = "Supervisor"
  slug         = "supervisor"

  order = 3

  url  = "http://localhost:8079"
  icon = "/icon/widgets.svg"

  subdomain = local.enable_subdomains
}

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

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count

  # we need to define a relation table in locals because we can't simply access resources like this: docker_image["javascript"]
  # we need to access [0] because we define a count in the docker_image's definition
  image = local.images[data.coder_parameter.docker_image.value][0].image_id

  # Use privileged mode instead of sysbox-runc for Docker-in-Docker functionality
  privileged = true
  
  name     = "coder-${local.user_name}-${local.workspace_name}"
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