using System;
using System.Security.Cryptography.X509Certificates;
using System.Threading.Tasks;
using Common.KeyVault;
using Microsoft.Azure.KeyVault;
using Microsoft.Identity.Client;

namespace Common.Auth
{
    /// <summary>
    ///
    /// </summary>
    public class AccessTokenHelper
    {
        public static async Task<string> GetAccessToken(
            AadAppSettings settings,
            KeyVaultSettings vaultSettings = null,
            IKeyVaultClient kvClient = null)
        {
            if (!string.IsNullOrEmpty(settings.ClientCertName))
            {
                if (kvClient == null)
                {
                    throw new ArgumentNullException(nameof(kvClient));
                }

                if (vaultSettings == null)
                {
                    throw new ArgumentNullException(nameof(vaultSettings));
                }
            }
            else if (string.IsNullOrEmpty(settings.ClientSecret))
            {
                throw new ArgumentNullException("ClientSecret not specified", nameof(settings));
            }

            IConfidentialClientApplication app;
            if (!string.IsNullOrEmpty(settings.ClientCertName) && vaultSettings != null)
            {
                var cert = await kvClient.GetCertificateAsync(vaultSettings.VaultUrl, settings.ClientCertName);
                var pfx = new X509Certificate2(cert.Cer);
                app = ConfidentialClientApplicationBuilder.Create(settings.ClientId)
                    .WithCertificate(pfx)
                    .WithAuthority(settings.Authority)
                    .Build();
            }
            else if (!string.IsNullOrEmpty(settings.ClientSecret))
            {
                app = ConfidentialClientApplicationBuilder
                    .Create(settings.ClientId)
                    .WithClientSecret(settings.ClientSecret)
                    .WithAuthority(settings.Authority)
                    .Build();
            }
            else
            {
                throw new ArgumentException("Either client secret or cert must be specified", nameof(settings));
            }

            try
            {
                var result = await app.AcquireTokenForClient(settings.Scopes).ExecuteAsync();
                return result.AccessToken;
            }
            catch (MsalServiceException ex) when (ex.Message.Contains("AADSTS70011"))
            {
                // Invalid scope. The scope has to be of the form "https://resourceurl/.default"
                // Mitigation: change the scope to be as expected
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine("Scope provided is not supported");
                Console.ResetColor();
            }

            return null;
        }
    }
}