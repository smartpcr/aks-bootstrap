using bootstrap.client.Collector;
using bootstrap.client.Data;
using bootstrap.client.Interfaces;
using bootstrap.client.Readers;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using System;
using System.Threading.Tasks;

namespace bootstrap.client
{
    public class Program
    {
        private readonly string fileName;
        private readonly IQueryReader reader;
        private readonly IQueryRegistry registry;
        private readonly IAnswerCollector collector;

        public Program(string fileName,
            IQueryReader reader,
            IQueryRegistry registry,
            IAnswerCollector collector
           )
        {
            this.fileName = fileName;
            this.reader = reader;
            this.registry = registry;
            this.collector = collector;
        }

        public async Task<Program> ReadQueriesAsync()
        {
            var queryNodes = await reader.ReadQueryNodesAsync(fileName);
            foreach(var node in queryNodes)
            {
                registry.RegisterNode(node);
            }
            return this;
        }

        public async Task<Program> CollectAnswersAsync()
        {
            collector.Collect();
            return await Task.FromResult(this);
        }

        public static void Main(string[] args)
        {
            var serviceProvider = ConfigureApplication();
            new Program("",
                serviceProvider.GetRequiredService<IQueryReader>(),
                serviceProvider.GetRequiredService<IQueryRegistry>(),
                serviceProvider.GetRequiredService<IAnswerCollector>())
                .ReadQueriesAsync().GetAwaiter().GetResult()
                .CollectAnswersAsync().GetAwaiter().GetResult();
        }

        private static IServiceProvider ConfigureApplication()
        {
            var serviceProvider = new ServiceCollection()
                .AddLogging()
                .AddTransient<IQueryReader, QueryReader>()
                .AddSingleton<IQueryRegistry, QueryRegistry>()
                .AddTransient<IQueryEnumerator, QueryEnumerator>()
                .AddTransient<IQueryRenderer, QueryRenderer>()
                .AddTransient<IAnswerCollector, AnswerCollector>()
                .BuildServiceProvider();

            //configure console logging
            serviceProvider
                .GetService<ILoggerFactory>()
                .AddConsole(LogLevel.Debug);
            return serviceProvider;
        }
    }
}
