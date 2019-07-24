using System;
using System.IO;
using System.Security.Cryptography.X509Certificates;
using Microsoft.Azure.KeyVault;
using Microsoft.Azure.Services.AppAuthentication;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Clients.ActiveDirectory;

namespace Common.KeyVault
{
    public static class KeyVaultBuilder
    {
        public static IServiceCollection AddKeyVault(this IServiceCollection services)
        {
            var serviceProvider = services.BuildServiceProvider();
            var serviceContext = serviceProvider.GetRequiredService<IOptions<ServiceContext>>().Value;
            var settings = serviceProvider.GetRequiredService<IOptions<KeyVaultSettings>>().Value;

            IKeyVaultClient keyVaultClient;
            if (serviceContext.Orchestrator == OrchestratorType.K8S ||
                serviceContext.Orchestrator == OrchestratorType.SF)
            {
                // use pod identity
                var azureServiceTokenProvider = new AzureServiceTokenProvider();
                keyVaultClient = new KeyVaultClient(
                    new KeyVaultClient.AuthenticationCallback(
                        azureServiceTokenProvider.KeyVaultTokenCallback));
            }
            else
            {
                // use mounted secret
                KeyVaultClient.AuthenticationCallback callback = async (authority, resource, scope) =>
                {
                    var authContext = new AuthenticationContext(authority);
                    var clientCertFile = Path.Combine(
                        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".secrets"),
                        settings.ClientCertFile);
                    var certificate = new X509Certificate2(clientCertFile);
                    var clientCred = new ClientAssertionCertificate(settings.ClientId, certificate);
                    var result = await authContext.AcquireTokenAsync(resource, clientCred);

                    if (result == null)
                        throw new InvalidOperationException("Failed to obtain the JWT token");

                    return result.AccessToken;
                };
                keyVaultClient = new KeyVaultClient(callback);
            }
            services.AddSingleton(keyVaultClient);

            return services;
        }
    }
}