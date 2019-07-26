using System;
using System.Diagnostics;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using Common.Auth;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Polly;
using Polly.Extensions.Http;

namespace Common.Client
{
    /// <summary>
    ///
    /// </summary>
    public static class HttpClientBuilder
    {
        public static IHttpClientBuilder AddClient<TInterface, TImplementation>(this IServiceCollection services, string settingName)
            where TImplementation : HttpClientBase, TInterface
            where TInterface: class
        {
            var serviceProvider = services.BuildServiceProvider();
            var settingOptionsSnapshot = serviceProvider.GetRequiredService<IOptionsSnapshot<HttpClientSettings>>();
            var settings = settingOptionsSnapshot.Get(settingName);
            var authSetting = serviceProvider.GetRequiredService<IOptions<AadAppSettings>>().Value;

            void ConfigureClient(IServiceProvider _, HttpClient client)
            {
                client.BaseAddress = new Uri(settings.EndpointUrl);
                var defaultRequetHeaders = client.DefaultRequestHeaders;
                if (defaultRequetHeaders.Accept.All(m => m.MediaType != "application/json"))
                {
                    defaultRequetHeaders.Accept?.Add(new MediaTypeWithQualityHeaderValue("application/json"));
                }

                if (!settings.AllowAnonymousAccess)
                {
                    var accessToken = GetBearerToken(authSetting).GetAwaiter().GetResult();
                    defaultRequetHeaders.Add("Authorization", accessToken);
                }

                /*defaultRequetHeaders.Add("request-id", Activity.Current.Id);
                Console.WriteLine($"Operation sent to request header: {Activity.Current.Id}");*/
            }

            return services.AddHttpClient<TInterface, TImplementation>(ConfigureClient)
                .AddPolicyHandler(GetTimeoutPolicy(settings))
                .AddPolicyHandler(request => GetRetryPolicy(request, settings))
                .AddPolicyHandler(GetCircuitBreakerPolicy(settings));
        }

        private static async Task<string> GetBearerToken(AadAppSettings authSettings)
        {
            return await AccessTokenHelper.GetAccessToken(authSettings);
        }

        private static IAsyncPolicy<HttpResponseMessage> GetTimeoutPolicy(HttpClientSettings settings)
        {
            return Policy.TimeoutAsync<HttpResponseMessage>(TimeSpan.FromSeconds(settings.TimeoutInSeconds));
        }

        private static IAsyncPolicy<HttpResponseMessage> GetCircuitBreakerPolicy(HttpClientSettings settings)
        {
            return HttpPolicyExtensions
                .HandleTransientHttpError()
                .CircuitBreakerAsync(settings.CircuitBreakMaxRetries, TimeSpan.FromSeconds(settings.CircuitBreakBackoffInSeconds));
        }

        private static IAsyncPolicy<HttpResponseMessage> GetRetryPolicy(HttpRequestMessage request, HttpClientSettings settings)
        {
            var retryPolicy = HttpPolicyExtensions.HandleTransientHttpError().RetryAsync(settings.MaxRetryCount);
            var noOp = Policy.NoOpAsync().AsAsyncPolicy<HttpResponseMessage>();
            return request.Method == HttpMethod.Get ? retryPolicy : noOp;
        }

    }
}