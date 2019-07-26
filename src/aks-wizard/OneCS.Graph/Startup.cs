using Common;
using Common.Auth;
using Common.Client;
using Common.KeyVault;
using Common.Metrics;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using OneCS.Graph.Client;

namespace OneCS.Graph
{
    public class Startup
    {
        public Startup(IConfiguration configuration)
        {
            Configuration = configuration;
        }

        public IConfiguration Configuration { get; }

        public void ConfigureServices(IServiceCollection services)
        {
            services.AddSingleton(Configuration);
            services.TryAddSingleton<IHttpContextAccessor, HttpContextAccessor>();

            // options
            services.AddOptions();

            // for kv client
            services.Configure<KeyVaultSettings>(Configuration.GetSection(nameof(KeyVaultSettings)));
            services.AddKeyVault();

            // for logging & metrics
            services.Configure<ServiceContext>(Configuration.GetSection(nameof(ServiceContext)));
            services.AddLogging(loggingBuilder =>
            {
                loggingBuilder.ClearProviders();
                loggingBuilder.AddConsole();
                if (Configuration.IsAppInsightsEnabled())
                {
                    services.AddAppInsights(); // for both metrics and logging
                }
            });

            // aad auth
            services.Configure<AadAppSettings>(Configuration.GetSection(nameof(AadAppSettings)));
            services.AddAuthentication();

            // http client
            services.Configure<HttpClientSettings>(nameof(ServiceTreeClientSettings),
                Configuration.GetSection(nameof(ServiceTreeClientSettings)));
            services.AddClient<IServiceTreeClient, ServiceTreeClient>(nameof(ServiceTreeClientSettings));

            services.AddMvc().SetCompatibilityVersion(CompatibilityVersion.Version_2_2);
        }

        public void Configure(IApplicationBuilder app, IHostingEnvironment env)
        {
            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
            }
            else
            {
                app.UseHsts();
            }

            if (Configuration.IsPrometheusEnabled())
            {
                app.UsePrometheus(Configuration);
            }

            app.UseHttpsRedirection();
            app.UseMvc();
        }
    }
}
