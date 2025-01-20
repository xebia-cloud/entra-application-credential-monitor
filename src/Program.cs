using Azure.Identity;
using Azure.Monitor.OpenTelemetry.Exporter;
using Microsoft.Graph;
using OpenTelemetry.Logs;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Xebia.Monitoring.Entra.ApplicationSecrets;

var host = Host.CreateDefaultBuilder(args)
    .ConfigureServices((host, services) =>
    {
        var azureCredential = new DefaultAzureCredential();
        services.AddSingleton(_ => new GraphServiceClient(azureCredential));
        
        services.AddOpenTelemetry()
            .ConfigureResource(resource => {
                resource.AddService(serviceName: "Xebia.Monitoring.Entra.ApplicationSecrets");
            })
            .WithTracing(builder =>
            {
                builder.AddSource("Xebia.Monitoring.Entra.ApplicationSecrets.*");
                if (host.HostingEnvironment.IsDevelopment())
                {
                    builder.AddConsoleExporter();
                }
                else
                {
                    builder.AddAzureMonitorTraceExporter();
                }
            })
            .WithMetrics(builder =>
            {
                builder.AddMeter("Xebia.Monitoring.Entra.ApplicationSecrets.*");
                if (host.HostingEnvironment.IsDevelopment())
                {
                    builder.AddConsoleExporter();
                }
                else
                {
                    builder.AddAzureMonitorMetricExporter();
                }
            })
            .WithLogging(builder => { },
                options =>
                {
                    if (!host.HostingEnvironment.IsDevelopment())
                    {
                        options.AddAzureMonitorLogExporter();
                    }
                });

        services.AddTransient<ApplicationCredentialMonitor>();
    })
    .Build();

await host.StartAsync();

var monitor = host.Services.GetRequiredService<ApplicationCredentialMonitor>();
await monitor.Monitor();

await host.StopAsync();
host.Dispose();
