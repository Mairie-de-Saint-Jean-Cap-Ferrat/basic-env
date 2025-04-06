terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

resource "docker_image" "dev_image" {
  name         = "ghcr.io/mairie-de-saint-jean-cap-ferrat/basic-env/base:latest"
  keep_locally = true
}

resource "docker_container" "dev_container" {
  image = docker_image.dev_image.image_id
  name  = "coder-dev-environment"
  
  # Use privileged mode for Docker-in-Docker functionality
  privileged = true
  
  # Container hostname
  hostname = "dev"
  
  # Network settings
  network_mode = "bridge"
  
  # Port mappings
  ports {
    internal = 8000
    external = 8000
  }
  
  # Mount Docker socket for Docker-in-Docker
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = false
  }
  
  # Mount home directory
  volumes {
    host_path      = "/home/coder"
    container_path = "/home/coder"
    read_only      = false
  }
  
  # Mount workspace
  volumes {
    host_path      = "/workspaces"
    container_path = "/workspaces"
    read_only      = false
  }
  
  # Environment variables
  env = [
    "TZ=Europe/Paris",
    "LANG=fr_FR.UTF-8"
  ]
}