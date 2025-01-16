# Entra ID Application Credentials Monitor

This application publishes metrics on Entra ID application secret- or certificate credential use.

The application is intended to run frequently such that you can manage application credential use and expiry.

## Exported Metrics

The following application metrics are exported:

- Secret Count, Total count of credentials associated with application

The values are bound to the application name and client id.


The following application credential metrics are exported:

- Secret Age, Age of credential in days
- Secret Expiry, Time to expiry of credential in days

The values are bound to the application name, client id, secret name and secret id.

## View metrics

In the log analytics workspace, view the expiring secrets graph using:

```kql
AppMetrics 
| where TimeGenerated >= ago(30d)
| where AppRoleName == "Xebia.Monitoring.Entra.ApplicationSecrets" and Name == "entra.app_secret.expiry"
| extend app = tostring(Properties.Application), key = tostring(Properties.Key)
| summarize DaysRemaining = max(Max) by bin(TimeGenerated, 1h), app, key
| render timechart 
```

Similarly, view all expired secrets using:

```kql
AppMetrics 
| where TimeGenerated >= ago(1h)
| where AppRoleName == "Xebia.Monitoring.Entra.ApplicationSecrets" and Name == "entra.app_secret.expiry"
| extend app = tostring(Properties.Application), key = tostring(Properties.Key)
| summarize DaysRemaining = min(Min) by app, key
| where DaysRemaining == 0.0
| project app, key
| render table
```

Or monitor the count of secrets using:

```kql
AppMetrics 
| where TimeGenerated >= ago(30d)
| where AppRoleName == "Xebia.Monitoring.Entra.ApplicationSecrets" and Name == "entra.app_secret.count"
| extend app = tostring(Properties.Application)
| summarize SecretCount = max(Max) by bin(TimeGenerated, 1h), app
| render table 
| order by SecretCount desc
```


## Deploy

Start required tools

```bash
sudo systemctl start docker
```

Ensure required credentials

```bash
az login
```

Deploy the infrastructure

```bash
cd terraform
terraform init
terraform apply -var="alert_receiver_email=your@email.com"
```

