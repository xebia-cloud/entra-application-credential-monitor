terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.15"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.15"
    }

    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "azuread" {
}

provider "azurerm" {
  subscription_id = "2cbec894-fe09-4977-8edc-b36255e9e628"

  resource_provider_registrations = "none"

  features {
  }
}

provider "docker" {
  registry_auth {
    address  = azurerm_container_registry.secret_monitor.login_server
    username = azurerm_container_registry_token.secret_monitor_cicd.name
    password = azurerm_container_registry_token_password.secret_monitor_cicd.password1[0].value
  }
}