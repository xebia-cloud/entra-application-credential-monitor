namespace Xebia.Monitoring.Entra.ApplicationSecrets;

public class Application {
    public string Id { get; }
    public string ClientId { get; }
    public string? DisplayName { get; }
    public List<ApplicationCredential> Credentials { get; }

    public Application(Microsoft.Graph.Models.Application application) {
        Id = application.Id!;
        ClientId = application.AppId!;
        DisplayName = application.DisplayName;

        var certificates = application.KeyCredentials!.Select(cert => new ApplicationCredential(this, cert));
        var passwords = application.PasswordCredentials!.Select(pass => new ApplicationCredential(this, pass));

        Credentials = certificates.Concat(passwords)
            .ToList();
    }

    public KeyValuePair<string, object?>[] AsTags() {
        var tags = new Dictionary<string, object?>
        {
            { "ApplicationId", ClientId },
            { "Application", DisplayName ?? ClientId },
        };

        return [.. tags];
    }
}
