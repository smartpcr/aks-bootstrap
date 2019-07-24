using System.Threading;
using System.Threading.Tasks;
using Common;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Wizard.Assets;

namespace Wizard
{
    class Program
    {
        static Program()
        {
            SynchronizationContext.SetSynchronizationContext(new SynchronizationContext());
        }

        static void Main(string[] args)
        {
            var builder = new HostBuilder()
                .ConfigureAppConfiguration((hostingContext, configBuilder) =>
                {
                    configBuilder.AddJsonFile("appsettings.json", optional: true);
                })
                .ConfigureServices((hostingContext, services) =>
                {
                    services.TryAddSingleton(hostingContext.Configuration);
                    services.AddOptions();
                    services.Configure<ServiceContext>(
                        hostingContext.Configuration.GetSection(nameof(ServiceContext)));

                    services.AddLogging(loggingBuilder =>
                    {
                        loggingBuilder.ClearProviders();
                        loggingBuilder.AddConfiguration(hostingContext.Configuration.GetSection("Logging"));

                        loggingBuilder.AddConsole();
                    });

                    services.TryAddSingleton<AssetManager>();
                    services.TryAddSingleton<InfraBuilder>();
                    services.TryAddSingleton<App>();
                });

            using (var host = builder.Build())
            {
                var app = host.Services.GetRequiredService<App>();
                app.Run(args);
            }

        }
    }
}
