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
    public class SolutionBuilder
    {
        private readonly AssetManager _assetManager;
        private readonly ILoggerFactory _loggerFactory;
        private readonly ILogger<SolutionBuilder> _logger;

        public SolutionBuilder(AssetManager assetManager, ILoggerFactory loggerFactory)
        {
            _assetManager = assetManager;
            _loggerFactory = loggerFactory;
            _logger = loggerFactory.CreateLogger<SolutionBuilder>();
        }

        public void GenerateCode(string manifestFile, string solutionFolder)
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

            var sortedComponents = _assetManager.GetAllAssetsWithObjPath()
                .Where(c => c.Kind == AssetKind.Code || c.Kind == AssetKind.Shared)
                .OrderBy(c => c.SortOrder)
                .ToList();
            var validator = new AssetValidator(_assetManager, _loggerFactory);
            validator.TryToValidateAssets(sortedComponents);

            // update solution file
            var product = _assetManager.Get(AssetType.Prodct) as Product;
            if (product == null)
            {
                throw new Exception("Missing dependency [Product]");
            }
            var defaultSolutionFile = Path.Join(solutionFolder, $"{product.Name}.sln");
            if (sortedComponents.FirstOrDefault(c => c.Type == AssetType.Service) is Services services)
            {
                foreach (var service in services.Items.OfType<Service>())
                {
                    service.SolutionFile = service.SolutionFile ?? defaultSolutionFile;
                }
            }

            if (!Directory.Exists(solutionFolder))
            {
                Directory.CreateDirectory(solutionFolder);
            }
            var zipFilePath = Path.Join("Evidence", "solution.zip");
            if (!File.Exists(zipFilePath))
            {
                throw new Exception($"Unable to find solution bundle: {new FileInfo(zipFilePath).FullName}");
            }
            ZipFile.ExtractToDirectory(zipFilePath, solutionFolder, true);
            var solutionFile = Directory.GetFiles(solutionFolder, "*.sln", SearchOption.TopDirectoryOnly)
                .FirstOrDefault();
            if (!string.IsNullOrEmpty(solutionFile))
            {
                File.Copy(solutionFile, defaultSolutionFile, true);
                File.Delete(solutionFile);
            }

            var manifestYamlFile = Path.Combine(solutionFolder, "services.yaml");
            _logger.LogInformation($"Set manifest file to '{new FileInfo(manifestYamlFile).FullName}'");
            if (File.Exists(manifestYamlFile))
            {
                File.Delete(manifestYamlFile);
            }

            using (var writer = new StreamWriter(File.OpenWrite(manifestYamlFile)))
            {
                foreach (var asset in sortedComponents)
                {
                    asset.WriteYaml(writer, _assetManager, _loggerFactory);
                }
            }

            // replace "True" and "False"
            var yamlContent = File.ReadAllText(manifestYamlFile);
            var trueRegex = new Regex("\\bTrue\\b");
            yamlContent = trueRegex.Replace(yamlContent, "true");
            var falseRegex = new Regex("\\bFalse\\b");
            yamlContent = falseRegex.Replace(yamlContent, "false");
            File.WriteAllText(manifestYamlFile, yamlContent);
        }
    }
}