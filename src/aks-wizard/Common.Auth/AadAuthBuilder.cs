using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.AzureAD.UI;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Authorization;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace Common.Auth
{
    public static class AadAuthBuilder
    {
        public static IServiceCollection AddAadAuth(this IServiceCollection services)
        {
            var serviceProvider = services.BuildServiceProvider();
            var aadAppSettings = serviceProvider.GetRequiredService<IOptions<AadAppSettings>>().Value;


            services.Configure<CookiePolicyOptions>(options =>
            {
                // This lambda determines whether user consent for non-essential cookies is needed for a given request.
                options.CheckConsentNeeded = context => true;
                options.MinimumSameSitePolicy = SameSiteMode.None;
            });

            services.AddAuthentication(AzureADDefaults.AuthenticationScheme)
                .AddAzureAD(options =>
                {
                    options.ClientId = aadAppSettings.ClientId;
                    options.TenantId = aadAppSettings.TenantId;
                });

            services.Configure<OpenIdConnectOptions>(AzureADDefaults.OpenIdScheme, options =>
            {
                options.Authority = options.Authority + "/v2.0/";         // Microsoft identity platform
                options.TokenValidationParameters.ValidateIssuer = false; // accept several tenants (here simplified)
            });

            /*services.AddProtectWebApiWithMicrosoftIdentityPlatformV2(Configuration)
                .AddProtectedApiCallsWebApis(Configuration, new string[] { "user.read", "offline_access" })
                .AddInMemoryTokenCaches();*/

            services.AddMvc(options =>
                {
                    var policyBuilder = new AuthorizationPolicyBuilder();
                    policyBuilder.RequireAuthenticatedUser();
                    var policy = policyBuilder.Build();
                    options.Filters.Add(new AuthorizeFilter(policy));
                })
                .SetCompatibilityVersion(CompatibilityVersion.Version_2_2);

            return services;
        }
    }
}