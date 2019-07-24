using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Prometheus.Client.AspNetCore;
using Prometheus.Client.MetricServer;

namespace Common.Metrics
{
    public static class PrometheusBuilder
    {
        public static bool UsePrometheus(this IConfiguration configuration)
        {
            return configuration.GetSection(nameof(PrometheusSettings)) != null;
        }

        /// <summary>
        /// this is used in console (GenericHost) app
        /// </summary>
        /// <param name="services"></param>
        public static void AddPrometheus(this IServiceCollection services)
        {
            var serviceProvider = services.BuildServiceProvider();
            var settings = serviceProvider.GetRequiredService<IOptions<PrometheusSettings>>().Value;
            var metricServer = new MetricServer(null, new MetricServerOptions()
            {
                Port = settings.PortNumber,
                MapPath = settings.Route,
                Host = "localhost",
                UseHttps = settings.UseHttps
            });
            metricServer.Start();
        }

        /// <summary>
        /// this is used in web host
        /// </summary>
        /// <param name="app"></param>
        /// <param name="settings"></param>
        public static void AddPrometheus(this IApplicationBuilder app,
            PrometheusSettings settings)
        {
            app.UsePrometheusServer(options =>
            {
                options.UseDefaultCollectors = true;
                options.MapPath = settings.Route;
            });
        }

    }
}