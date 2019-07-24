using System.Collections.Generic;
using System.IO;
using System.Linq;
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

        public void Build(string manifestFile, string outputFolder)
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

            if (!Directory.Exists(outputFolder))
            {
                Directory.CreateDirectory(outputFolder);
            }

            var sortedComponents = _assetManager.GetAllAssetsWithObjPath();
            var valueYamlFile = Path.Combine(outputFolder, "values.yaml");
            if (File.Exists(valueYamlFile))
            {
                _logger.LogInformation(new FileInfo(valueYamlFile).FullName);

                File.Delete(valueYamlFile);
            }

            using (var writer = new StreamWriter(File.OpenWrite(valueYamlFile)))
            {
                foreach (var asset in sortedComponents)
                {
                    asset.WriteYaml(writer, _assetManager, _loggerFactory);
                }
            }
        }
    }
}