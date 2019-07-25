using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using Wizard.Assets;

namespace Wizard
{
    public class InfraBuilder
    {
        private readonly AssetManager _assetManager;
        private readonly ILoggerFactory _loggerFactory;
        private readonly ILogger<InfraBuilder> _logger;

        public InfraBuilder(AssetManager assetManager, ILoggerFactory loggerFactory)
        {
            _assetManager = assetManager;
            _loggerFactory = loggerFactory;
            _logger = loggerFactory.CreateLogger<InfraBuilder>();
        }

        public void BuildInfraSetupScript(string manifestFile, string outputFolder)
        {
            IEnumerable<IAsset> unresolvedAssets = null;
            var assets = AssetReader.Read(manifestFile);
            if (assets?.Any() == true)
            {
                foreach (var asset in assets)
                {
                    _assetManager.Add(asset);
                    unresolvedAssets = _assetManager.EvaluateUnfulfilledComponents(asset);
                }
            }

            if (unresolvedAssets?.Any() == true)
            {
                foreach (var asset in unresolvedAssets)
                {
                    _logger.LogWarning($"Unable to resolve {asset.Type}");
                    var missingDependencyTypes = asset.Dependencies.Where(d =>
                            string.IsNullOrEmpty(d.Key))
                        .Select(d => d.Type);
                    _logger.LogWarning($"Unresolved components: {string.Join(",", missingDependencyTypes)}");
                }
            }

            var sortedComponents = _assetManager.GetAllAssetsWithObjPath();
            var validator = new AssetValidator(_assetManager, _loggerFactory);
            validator.TryToValidateAssets(sortedComponents);
            var envName = "dev";
            var spaceName = Environment.UserName;
            if (sortedComponents.FirstOrDefault(c => c.Type == AssetType.Global) is Global global)
            {
                envName = global.EnvName;
                spaceName = global.SpaceName;
            }

            if (!Directory.Exists(outputFolder))
            {
                Directory.CreateDirectory(outputFolder);
            }
            var envFolder = Path.Join(outputFolder, "env", envName);
            if (!Directory.Exists(envFolder))
            {
                Directory.CreateDirectory(envFolder);
            }

            var spaceFolder = envFolder;
            if (!string.IsNullOrEmpty(spaceName))
            {
                spaceFolder = Path.Join(envFolder, spaceName);
            }
            if (!Directory.Exists(spaceFolder))
            {
                Directory.CreateDirectory(spaceFolder);
            }

            var zipFilePath = Path.Join("Evidence", "scripts.zip");
            if (!File.Exists(zipFilePath))
            {
                throw new Exception($"Unable to find script bundle: {new FileInfo(zipFilePath).FullName}");
            }
            ZipFile.ExtractToDirectory(zipFilePath, outputFolder, true);

            var valueYamlFile = Path.Combine(spaceFolder, "values.yaml");
            _logger.LogInformation($"Set values yaml file to '{new FileInfo(valueYamlFile).FullName}'");
            if (File.Exists(valueYamlFile))
            {
                File.Delete(valueYamlFile);
            }

            using (var writer = new StreamWriter(File.OpenWrite(valueYamlFile)))
            {
                foreach (var asset in sortedComponents)
                {
                    asset.WriteYaml(writer, _assetManager, _loggerFactory);
                }
            }

            // replace "True" and "False"
            var yamlContent = File.ReadAllText(valueYamlFile);
            var trueRegex = new Regex("\\bTrue\\b");
            yamlContent = trueRegex.Replace(yamlContent, "true");
            var falseRegex = new Regex("\\bFalse\\b");
            yamlContent = falseRegex.Replace(yamlContent, "false");
            File.WriteAllText(valueYamlFile, yamlContent);
        }
    }
}