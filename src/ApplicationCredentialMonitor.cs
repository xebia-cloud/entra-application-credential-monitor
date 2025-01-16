using System.Diagnostics.Metrics;
using Microsoft.Graph;
using Microsoft.Graph.Models;

namespace Xebia.Monitoring.Entra.ApplicationSecrets;

public class ApplicationCredentialMonitor
{
    private readonly ILogger<ApplicationCredentialMonitor> _logger;
    private readonly GraphServiceClient _graphClient;

    private readonly Gauge<int> _secretCount;
    private readonly Gauge<double> _secretAge;
    private readonly Gauge<double> _secretExpiry;

    public ApplicationCredentialMonitor(
        ILogger<ApplicationCredentialMonitor> logger,
        GraphServiceClient graphClient,
        IMeterFactory meterFactory)
    {
        _logger = logger;
        _graphClient = graphClient;

        var meter = meterFactory.Create("Xebia.Monitoring.Entra.ApplicationSecrets.Monitor");

        _secretCount = meter.CreateGauge<int>("entra.app_secret.count");
        _secretAge = meter.CreateGauge<double>("entra.app_secret.age", unit: "days");
        _secretExpiry = meter.CreateGauge<double>("entra.app_secret.expiry", unit: "days");
    }

    public async Task Monitor(CancellationToken stoppingToken = default)
    {
        _logger.LogInformation("Starting secret scan..");
        DateTimeOffset timeOfScan = DateTimeOffset.UtcNow;

        var applications = await _graphClient.Applications.GetAsync(null, stoppingToken);
        if (applications == null)
        {
            _logger.LogWarning("No applications found..");
        }
        else
        {
            await PageIterator<Microsoft.Graph.Models.Application, ApplicationCollectionResponse>
                .CreatePageIterator(_graphClient, applications, app =>
                {
                    var application = new Application(app);
                    ReportMetrics(application, timeOfScan);
                    return true;
                })
                .IterateAsync(stoppingToken);
        }

        _logger.LogInformation("Secret scan completed..");
    }

    private void ReportMetrics(Application app, DateTimeOffset timeOfScan)
    {
        using (_logger.BeginScope("Application[Id={AppId}, Name={AppName}]", app.ClientId, app.DisplayName)) {
            _logger.LogInformation("Processing application..");

            _secretCount.Record(app.Credentials.Count, app.AsTags());

            foreach (var cred in app.Credentials) {
                using (_logger.BeginScope("Credential[Id={KeyId}, Name={KeyName}]", cred.KeyId, cred.KeyName)) {
                    _logger.LogInformation("Processing application credential..");
                    
                    var credentialTags = cred.AsTags();
                    _secretAge.Record(cred.CalculateAgeInDays(timeOfScan), credentialTags);
                    _secretExpiry.Record(cred.CalculateExpiryInDays(timeOfScan), credentialTags);
                }
            }
        }
    }
}
