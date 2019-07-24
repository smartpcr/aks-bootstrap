using System;
using System.IO;
using Common;
using McMaster.Extensions.CommandLineUtils;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Wizard
{
    public class App : CommandLineApplication
    {
        private readonly ServiceContext _context;
        private readonly ILogger<App> _logger;
        private readonly InfraBuilder _infraBuilder;

        public App(IOptions<ServiceContext> context, ILogger<App> logger,
            InfraBuilder infraBuilder)
        {
            _context = context.Value;
            _logger = logger;
            _infraBuilder = infraBuilder;

            Name = _context.Role;
            Description = _context.Description;
            HelpOption("-o|--options", true);

            SetupInfraCommand();
            SetupAppCommand();
        }

        public void Run(string[] args)
        {
            _logger.LogInformation($"Started {_context.Role}");
            Execute(args);
        }

        private void SetupInfraCommand()
        {
            Command("infra", infraCmd =>
            {
                infraCmd.OnExecute(() =>
                {
                    Console.WriteLine("Specify subcommand: either 'gen' or 'run'");
                    infraCmd.ShowHelp();
                    return 1;
                });

                infraCmd.Command("gen", generateCmd =>
                    {
                        generateCmd.Description = "Generate infrastructure setup powershell scripts";
                        var manifestJsonFile = generateCmd.Argument("input-manifest-file", "manifest file").IsRequired();
                        var outputFolder = generateCmd.Argument("output-folder", "output folder").IsRequired();
                        generateCmd.OnExecute(() =>
                        {
                            _logger.LogInformation($"Generating infra scripts based on manifest {manifestJsonFile.Value} and write to {outputFolder.Value}");
                            _infraBuilder.Build(manifestJsonFile.Value, outputFolder.Value);
                        });
                    });

                infraCmd.Command("run", runCmd =>
                {
                    var scriptFolder = runCmd.Argument("input-folder", "input folder for generated infra scripts").IsRequired();
                    runCmd.OnExecute(() =>
                    {
                        var setupScriptFile = Path.Join(scriptFolder.Value, "deploy", "setup-infrastructure.ps1");
                        _logger.LogInformation($"Running powershell {setupScriptFile}");
                    });
                });
            });
        }

        private void SetupAppCommand()
        {
            Command("app", appCmd =>
            {
                appCmd.OnExecute(() =>
                {
                    Console.WriteLine("Specify subcommand: either 'gen' or 'deploy' or 'run'");
                    appCmd.ShowHelp();
                    return 1;
                });

                appCmd.Command("gen", genCmd =>
                {
                    genCmd.Description = "Generate services code";
                    var manifestJsonFile = genCmd.Argument("input-manifest-file", "manifest file").IsRequired();
                    var outputFolder = genCmd.Argument("output-folder", "output folder").IsRequired();
                    genCmd.OnExecute(() =>
                    {
                        _logger.LogInformation(
                            $"Generating code based on manifest {manifestJsonFile.Value} and write to {outputFolder.Value}");
                    });
                });

                appCmd.Command("deploy", deployCmd =>
                {
                    var serviceManifestFile = deployCmd.Argument("service-manifest-file", "generated service manifest file").IsRequired();
                    var scriptFolder = deployCmd.Argument("script-folder", "generated script folder").IsRequired();

                    deployCmd.OnExecute(() =>
                    {
                        var setupScriptFile = Path.Join(scriptFolder.Value, "deploy", "deploy-apps.ps1");
                        _logger.LogInformation($"Running powershell {setupScriptFile} based on manifest {serviceManifestFile.Value}");
                    });
                });

                appCmd.Command("run", runCmd =>
                {
                    var serviceManifestFile = runCmd.Argument("service-manifest-file", "generated service manifest file").IsRequired();
                    var scriptFolder = runCmd.Argument("script-folder", "generated script folder").IsRequired();

                    runCmd.OnExecute(() =>
                    {
                        var setupScriptFile = Path.Join(scriptFolder.Value, "deploy", "deploy-apps.ps1 -IsLocal");
                        _logger.LogInformation($"Running powershell '{setupScriptFile}' using manifest '{serviceManifestFile.Value}'");
                    });
                });
            });
        }
    }
}