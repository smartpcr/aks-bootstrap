using bootstrap.client.Collector;
using bootstrap.client.Data;
using bootstrap.client.Extensions;
using bootstrap.client.Interfaces;
using bootstrap.client.Readers;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;
using System;
using System.IO;
using System.Threading.Tasks;

namespace bootstrap.client
{
    public class Program
    {
        private readonly string inFileName;
        private readonly string outFileName;
        private readonly IQueryReader reader;
        private readonly IQueryRegistry registry;
        private readonly IAnswerCollector collector;
        private readonly ILogger<Program> logger;

        public Program(string inFileName,
            string outFileName,
            IQueryReader reader,
            IQueryRegistry registry,
            IAnswerCollector collector,
            ILogger<Program> logger
           )
        {
            this.inFileName = inFileName;
            this.outFileName = outFileName;
            this.reader = reader;
            this.registry = registry;
            this.collector = collector;
            this.logger = logger;
        }

        public async Task<Program> ReadQueriesAsync()
        {
            var queryNodes = await reader.ReadQueryNodesAsync(inFileName);
            foreach(var node in queryNodes)
            {
                registry.RegisterNode(node);
            }
            return this;
        }

        public async Task<Program> CollectAnswersAsync()
        {
            collector.Collect();
            logger.LogInformation("Finished collecting all answers .. ");
            return await Task.FromResult(this);
        }

        public async Task<Program> WriteCollectedAnswers()
        {
            await registry.WriteAync(outFileName);
            logger.LogInformation($"Finished writing values json in {outFileName} ..");
            return this;
        }

        public static void Main(string[] args)
        {
            var appInput = GetInput(args);
            var inputFileName = appInput.InputFileName;
            var outputFileName = appInput.OutFileName;
            var serviceProvider = ConfigureApplication();
            new Program(inputFileName, outputFileName,
                serviceProvider.GetRequiredService<IQueryReader>(),
                serviceProvider.GetRequiredService<IQueryRegistry>(),
                serviceProvider.GetRequiredService<IAnswerCollector>(),
                serviceProvider.GetService<ILogger<Program>>())
                .ReadQueriesAsync().GetAwaiter().GetResult()
                .CollectAnswersAsync().GetAwaiter().GetResult()
                .WriteCollectedAnswers().GetAwaiter().GetResult();
        }

        private static AppInput GetInput(string[] args)
        {
            if(args.Length < 2)
            {
                throw new InvalidOperationException("No sufficient args supplied");
            }
            var inFile = args[0];
            if(!File.Exists(inFile))
            {
                throw new ArgumentException("Supplied file doesn't exits");
            }
            var outFile = args[1];
            var location = Path.GetDirectoryName(outFile);
            
            if (!Directory.Exists(location))
            {
                throw new ArgumentException("Invalid output file supplied");
            }
            return new AppInput(inFile, outFile);
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
