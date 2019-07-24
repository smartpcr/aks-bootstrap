using System.IO;
using System.Reflection;
using Microsoft.ApplicationInsights.Channel;
using Microsoft.ApplicationInsights.DependencyCollector;
using Microsoft.ApplicationInsights.Extensibility;
using Microsoft.ApplicationInsights.ServiceFabric;
using Microsoft.ApplicationInsights.WindowsServer.TelemetryChannel;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Internal;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Common.Metrics
{
    public static class AppInsightsBuilder
    {
         public static void AddAppInsights(this IServiceCollection services)
        {
            // force to use aspnetcore hosting environment so that all modules can be loaded
            services.TryAddSingleton<IHostingEnvironment, HostingEnvironment>();

            var serviceProvider = services.BuildServiceProvider();
            var settings = serviceProvider.GetRequiredService<IOptions<AppInsightsSettings>>().Value;
            var serviceContext = serviceProvider.GetRequiredService<IOptions<ServiceContext>>().Value;
            var env = serviceProvider.GetRequiredService<IHostingEnvironment>();

            var appInsightsConfig = TelemetryConfiguration.Active;
            appInsightsConfig.InstrumentationKey = settings.InstrumentationKey;
            appInsightsConfig.TelemetryInitializers.Add(new OperationCorrelationTelemetryInitializer());
            appInsightsConfig.TelemetryInitializers.Add(new HttpDependenciesParsingTelemetryInitializer());
            appInsightsConfig.TelemetryInitializers.Add(new ContextTelemetryInitializer(serviceContext));

            var appFolder = Path.GetDirectoryName(Assembly.GetEntryAssembly()?.Location);
            services.TryAddSingleton<ITelemetryChannel>(new ServerTelemetryChannel()
            {
                StorageFolder = appFolder,
                DeveloperMode = true
            });

            services.AddApplicationInsightsTelemetry(o =>
            {
                o.InstrumentationKey = settings.InstrumentationKey;
                o.EnableDebugLogger = !env.IsProduction();
                o.AddAutoCollectedMetricExtractor = true;
                o.EnableAdaptiveSampling = false;
                o.DependencyCollectionOptions.EnableLegacyCorrelationHeadersInjection = true;
                o.RequestCollectionOptions.EnableW3CDistributedTracing = true;
                o.RequestCollectionOptions.InjectResponseHeaders = true;
                o.RequestCollectionOptions.TrackExceptions = true;
            });

            switch (serviceContext.Orchestrator)
            {
                case OrchestratorType.K8S:
                    services.AddApplicationInsightsKubernetesEnricher();
                    break;
                case OrchestratorType.SF:
                    services.AddSingleton<ITelemetryInitializer>(_ => new FabricTelemetryInitializer());
                    break;
            }

            // logging
            services.AddLogging(loggingBuilder =>
            {
                loggingBuilder.AddApplicationInsights(settings.InstrumentationKey);
            });
        }

        public static bool UseAppInsights(this IConfiguration configuration)
        {
            return configuration.GetSection(nameof(AppInsightsSettings)) != null;
        }
    }
}