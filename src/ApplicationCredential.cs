using Microsoft.Graph.Models;

namespace Xebia.Monitoring.Entra.ApplicationSecrets;

public class ApplicationCredential {
    public Application Application { get; }

    public string KeyId { get; }
    public string? KeyName { get; }

    public DateTimeOffset? StartDateTime { get; }
    public DateTimeOffset? EndDateTime { get; }

    public ApplicationCredential(Application application, PasswordCredential credential) {
        Application = application;

        KeyId = (credential.KeyId ?? Guid.Empty).ToString();
        KeyName = credential.DisplayName;
        StartDateTime = credential.StartDateTime;
        EndDateTime = credential.EndDateTime;
    }

    public ApplicationCredential(Application application, KeyCredential credential) {
        Application = application;

        KeyId = (credential.KeyId ?? Guid.Empty).ToString();
        KeyName = credential.DisplayName;
        StartDateTime = credential.StartDateTime;
        EndDateTime = credential.EndDateTime;
    }

    /// <summary>
    /// Calculates age of secret in days.
    /// </summary>
    /// <param name="now">Reference date to compare to.</param>
    /// <returns>Age of secret in days. 0 when in future. -1 when unknown.</returns>
    public double CalculateAgeInDays(DateTimeOffset now) {
        if (!StartDateTime.HasValue) {
            return -1.0;
        }

        var secretAge = now.Subtract(StartDateTime.Value);
        return Math.Max(secretAge.TotalDays, 0.0); // If in future (negative value), report 0.
    }

    /// <summary>
    /// Calculates days to secret expiry.
    /// </summary>
    /// <param name="now">Reference date to compare to.</param>
    /// <returns>Days to expire. 0 when expired. 5 years in future when unspecified.</returns>
    public double CalculateExpiryInDays(DateTimeOffset now) {
        if (!EndDateTime.HasValue) {
            return now.AddYears(5).Subtract(now).TotalDays;
        }

        var secretExpiry = EndDateTime.Value.Subtract(now);
        return Math.Max(secretExpiry.TotalDays, 0.0); // If expired (negative value), report 0.
    }

    public KeyValuePair<string, object?>[] AsTags() {
        var applicationTags = Application.AsTags();
        var credentialTags = new Dictionary<string, object?>
        {
            { "KeyId", KeyId },
            { "Key", KeyName ?? KeyId }
        };

        return [.. applicationTags, .. credentialTags];
    }
}
