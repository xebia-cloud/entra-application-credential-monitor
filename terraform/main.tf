resource "azurerm_resource_group" "secret_monitor" {
  name     = "entra-secret-monitor"
  location = "West Europe"
}

# Graph references
data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}


# Log workspace
resource "azurerm_log_analytics_workspace" "secret_monitor" {
  resource_group_name = azurerm_resource_group.secret_monitor.name
  location            = "West Europe"
  name                = "secretmonitor"

  sku               = "PerGB2018"
  retention_in_days = 365
}

resource "azurerm_application_insights" "secret_monitor" {
  resource_group_name = azurerm_resource_group.secret_monitor.name
  location            = "West Europe"
  name                = "secretmonitor"

  application_type = "web"
  workspace_id     = azurerm_log_analytics_workspace.secret_monitor.id
}

resource "azurerm_monitor_action_group" "secret_monitor" {
  resource_group_name = azurerm_resource_group.secret_monitor.name
  name                = "ApplicationCredentialsAlert"
  short_name          = "appcred"

  email_receiver {
    name          = var.alert_receiver_email
    email_address = var.alert_receiver_email
  }
}

# NOTE: azurerm_monitor_metric_alert does not yet recognize the custom metric dimensions.. relying on azurerm_monitor_scheduled_query_rules_alert_v2 instead.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "secret_expires_in_90_days" {
  resource_group_name = azurerm_resource_group.secret_monitor.name
  location            = "West Europe"
  name                = "Application credential expires in 90 days"

  severity = 2 # Warning

  action {
    action_groups = [
      azurerm_monitor_action_group.secret_monitor.id,
    ]
  }

  evaluation_frequency    = "PT30M"
  window_duration         = "PT1H"
  auto_mitigation_enabled = true # NOTE: Prevent alert from firing every evaluation

  scopes = [
    azurerm_application_insights.secret_monitor.id,
  ]

  criteria {
    query = <<-EOT
      customMetrics 
      | where name == "entra.app_secret.expiry"
      | extend
          daysRemaining = value,
          app = tostring(customDimensions.Application),
          key = tostring(customDimensions.Key)
      | project timestamp, app, key, daysRemaining
      EOT

    time_aggregation_method = "Minimum"
    metric_measure_column   = "daysRemaining"
    operator                = "LessThan"
    threshold               = 90.0

    dimension {
      name     = "app"
      operator = "Include"
      values   = ["*"]
    }

    dimension {
      name     = "key"
      operator = "Include"
      values   = ["*"]
    }

  }
}



# Container registry
resource "azurerm_container_registry" "secret_monitor" {
  resource_group_name = azurerm_resource_group.secret_monitor.name
  location            = "West Europe"
  name                = "secretmonitor"

  sku           = "Premium"
  admin_enabled = false
}

resource "azurerm_container_registry_scope_map" "secret_monitor_cicd" {
  resource_group_name     = azurerm_resource_group.secret_monitor.name
  container_registry_name = azurerm_container_registry.secret_monitor.name
  name                    = "entra-secret-monitor-cicd-${substr(sha1(plantimestamp()), 0, 6)}" # Replace every time to ensure valid credential

  actions = [
    "repositories/entra-secret-monitor/content/read",
    "repositories/entra-secret-monitor/content/write"
  ]
}

resource "azurerm_container_registry_token" "secret_monitor_cicd" {
  resource_group_name     = azurerm_resource_group.secret_monitor.name
  container_registry_name = azurerm_container_registry.secret_monitor.name
  name                    = "entra-secret-monitor-cicd"
  scope_map_id            = azurerm_container_registry_scope_map.secret_monitor_cicd.id
}

resource "azurerm_container_registry_token_password" "secret_monitor_cicd" {
  container_registry_token_id = azurerm_container_registry_token.secret_monitor_cicd.id

  password1 {
    expiry = timeadd(timestamp(), "30m")
  }
}


# Application image
resource "docker_image" "secret_monitor_latest" {
  name = "${azurerm_container_registry.secret_monitor.login_server}/entra-secret-monitor:latest"

  build {
    context = "${path.root}/.."
  }

  triggers = { for f in fileset(path.root, "../src/*") : f => filesha1(f) }
}

resource "docker_registry_image" "secret_monitor_latest" {
  name          = docker_image.secret_monitor_latest.name
  keep_remotely = true
}


# Application identity
resource "azurerm_user_assigned_identity" "secret_monitor" {
  resource_group_name = azurerm_resource_group.secret_monitor.name
  location            = "West Europe"
  name                = "secret-monitor"
}

resource "azurerm_role_assignment" "secret_monitor_acr_pull_secret_monitor" {
  principal_type       = "ServicePrincipal"
  principal_id         = azurerm_user_assigned_identity.secret_monitor.principal_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.secret_monitor.id
}

resource "azuread_app_role_assignment" "secret_monitor_entra_application_read_all" {
  principal_object_id = azurerm_user_assigned_identity.secret_monitor.principal_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids["Application.Read.All"]
}


# Application infrastructure
resource "azurerm_resource_provider_registration" "microsoft_app" {
  name = "Microsoft.App"
}

resource "azurerm_container_app_environment" "secret_monitor" {
  resource_group_name = azurerm_resource_group.secret_monitor.name
  location            = "West Europe"
  name                = "Example-Environment"

  log_analytics_workspace_id = azurerm_log_analytics_workspace.secret_monitor.id

  depends_on = [
    azurerm_resource_provider_registration.microsoft_app,
  ]
}

resource "azurerm_container_app_job" "secret_monitor" {
  resource_group_name          = azurerm_resource_group.secret_monitor.name
  location                     = "West Europe"
  container_app_environment_id = azurerm_container_app_environment.secret_monitor.id
  name                         = "secret-monitor"

  replica_timeout_in_seconds = 600
  replica_retry_limit        = 3

  schedule_trigger_config {
    cron_expression          = "10,40 * * * *"
    parallelism              = 1
    replica_completion_count = 1
  }

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.secret_monitor.id,
    ]
  }

  registry {
    server   = azurerm_container_registry.secret_monitor.login_server
    identity = azurerm_user_assigned_identity.secret_monitor.id
  }

  template {
    container {
      name   = "monitor"
      image  = "${azurerm_container_registry.secret_monitor.login_server}/entra-secret-monitor:latest"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.secret_monitor.client_id
      }

      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.secret_monitor.connection_string
      }
    }
  }
}