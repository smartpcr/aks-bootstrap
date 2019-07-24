using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.AzureAD.UI;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Authorization;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Common.Auth
{
    public static class AadAuthBuilder
    {
        public static IServiceCollection AddAadAuth(this IServiceCollection services,
            IConfiguration configuration)
        {
            var aadAppSettings = new AadAppSettings();
            configuration.Bind("aad", aadAppSettings);

            services.Configure<CookiePolicyOptions>(options =>
            {
                // This lambda determines whether user consent for non-essential cookies is needed for a given request.
                options.CheckConsentNeeded = context => true;
                options.MinimumSameSitePolicy = SameSiteMode.None;
            });

            services.AddAuthentication(AzureADDefaults.AuthenticationScheme)
                .AddAzureAD(options => configuration.Bind("AzureAd", options));

            services.Configure<OpenIdConnectOptions>(AzureADDefaults.OpenIdScheme, options =>
            {
                options.Authority = options.Authority + "/v2.0/";         // Microsoft identity platform
                options.TokenValidationParameters.ValidateIssuer = false; // accept several tenants (here simplified)
            });

//            services.AddProtectWebApiWithMicrosoftIdentityPlatformV2(Configuration)
//                .AddProtectedApiCallsWebApis(Configuration, new string[] { "user.read", "offline_access" })
//                .AddInMemoryTokenCaches();

            services.AddMvc().SetCompatibilityVersion(CompatibilityVersion.Version_2_2);

            services.AddMvc(options =>
                {
                    var policyBuilder = new AuthorizationPolicyBuilder();
                    if (aadAppSettings.TokenType != AuthTokenType.None)
                    {
                        policyBuilder.RequireAuthenticatedUser();
                    }
                    var policy = policyBuilder.Build();
                    options.Filters.Add(new AuthorizeFilter(policy));
                })
                .SetCompatibilityVersion(CompatibilityVersion.Version_2_1);

            return services;
        }
    }
}