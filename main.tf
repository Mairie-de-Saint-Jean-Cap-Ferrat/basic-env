terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.21.0"
    }

    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }
  }
}

locals {
  enable_subdomains = true

  workspace_name = lower(data.coder_workspace.me.name)
  user_name = lower(data.coder_workspace.me.owner)

  images = {
    javascript = docker_image.javascript
    typescript = docker_image.typescript
    php = docker_image.php
    java = docker_image.java
    python = docker_image.python
    base = docker_image.base
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

provider "coder" {}
data "coder_workspace" "me" {}

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

    "SUPERVISOR_DIR" = "/usr/share/basic-env/supervisor"
  }

  startup_script = <<EOT
#!/bin/bash
echo "[+] Setting default shell"
SHELL=$(which $SHELL)
sudo chsh -s $SHELL $USER
sudo chsh -s $SHELL root

supervisord

echo "[+] Starting code-server"
supervisorctl start code-server

if [ "$VNC_ENABLED" = "true" ]
then
  echo "[+] Starting VNC"
  echo "${data.coder_parameter.vnc.value == "true" ? random_string.vnc_password[0].result : 0}" | tightvncpasswd -f > $HOME/.vnc/passwd
  
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

module "dotfiles" {
  source   = "registry.coder.com/modules/dotfiles/coder"
  version  = "1.0.14"

  coder_parameter_order = 5

  agent_id = coder_agent.dev.id
}

module "dotfiles-root" {
  source       = "registry.coder.com/modules/dotfiles/coder"
  version      = "1.0.14"

  user         = "root"
  dotfiles_uri = module.dotfiles.dotfiles_uri

  agent_id     = coder_agent.dev.id
}

module "git-config" {
  source = "registry.coder.com/modules/git-config/coder"
  version = "1.0.12"
  
  allow_username_change = true
  allow_email_change = true

  coder_parameter_order = 6

  agent_id = coder_agent.dev.id
}

module "coder-login" {
  source   = "registry.coder.com/modules/coder-login/coder"
  version  = "1.0.2"

  agent_id = coder_agent.dev.id
}

module "personalize" {
  source = "registry.coder.com/modules/personalize/coder"
  version = "1.0.2"

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

  url  = "http://localhost:8081?autoconnect=1&resize=scale&path=@${data.coder_workspace.me.owner}/${data.coder_workspace.me.name}.dev/apps/noVNC/websockify&password=${random_string.vnc_password[0].result}"
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
    value = data.coder_workspace.me.owner_id
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

  name = "ghcr.io/Mairie-de-Saint-Jean-Cap-Ferrat/basic-env/javascript-node:latest"
}

resource "docker_image" "javascript" {
  count = data.coder_parameter.docker_image.value == "javascript" ? 1 : 0

  name          = data.docker_registry_image.javascript[0].name
  pull_triggers = [data.docker_registry_image.javascript[0].sha256_digest]
}

data "docker_registry_image" "typescript" {
  count = data.coder_parameter.docker_image.value == "typescript" ? 1 : 0

  name = "ghcr.io/Mairie-de-Saint-Jean-Cap-Ferrat/basic-env/typescript-node:latest"
}

resource "docker_image" "typescript" {
  count = data.coder_parameter.docker_image.value == "typescript" ? 1 : 0

  name          = data.docker_registry_image.typescript[0].name
  pull_triggers = [data.docker_registry_image.typescript[0].sha256_digest]
}

data "docker_registry_image" "php" {
  count = data.coder_parameter.docker_image.value == "php" ? 1 : 0

  name = "ghcr.io/Mairie-de-Saint-Jean-Cap-Ferrat/basic-env/php:latest"
}

resource "docker_image" "php" {
  count = data.coder_parameter.docker_image.value == "php" ? 1 : 0

  name          = data.docker_registry_image.php[0].name
  pull_triggers = [data.docker_registry_image.php[0].sha256_digest]
}

data "docker_registry_image" "java" {
  count = data.coder_parameter.docker_image.value == "java" ? 1 : 0

  name = "ghcr.io/Mairie-de-Saint-Jean-Cap-Ferrat/basic-env/java:latest"
}

resource "docker_image" "java" {
  count = data.coder_parameter.docker_image.value == "java" ? 1 : 0

  name          = data.docker_registry_image.java[0].name
  pull_triggers = [data.docker_registry_image.java[0].sha256_digest]
}

data "docker_registry_image" "python" {
  count = data.coder_parameter.docker_image.value == "python" ? 1 : 0

  name = "ghcr.io/Mairie-de-Saint-Jean-Cap-Ferrat/basic-env/python:latest"
}

resource "docker_image" "python" {
  count = data.coder_parameter.docker_image.value == "python" ? 1 : 0

  name          = data.docker_registry_image.python[0].name
  pull_triggers = [data.docker_registry_image.python[0].sha256_digest]
}

data "docker_registry_image" "base" {
  count = data.coder_parameter.docker_image.value == "base" ? 1 : 0

  name = "ghcr.io/Mairie-de-Saint-Jean-Cap-Ferrat/basic-env/base:latest"
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

  # set runtime to use Sysbox to allow Docker in Docker
  runtime = "sysbox-runc"

  name     = "coder-${local.user_name}-${local.workspace_name}"
  hostname = local.workspace_name

  dns      = [
    "100.100.100.100",
    "192.168.0.70"
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
    value = data.coder_workspace.me.owner_id
  }

  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}