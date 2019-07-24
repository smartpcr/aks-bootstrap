using System;
using System.Collections.Generic;
using System.IO;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    public abstract class BaseAsset : IAsset
    {
        protected BaseAsset()
        {
            Key = Guid.NewGuid().ToString();
        }

        public string Key { get; }
        public abstract AssetType Type { get; }
        public abstract IList<Dependency> Dependencies { get; }
        public abstract int SortOrder { get; }

        public virtual void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory,
            int indent = 0)
        {
            var logger = loggerFactory.CreateLogger<BaseAsset>();
            foreach (var dependency in Dependencies)
            {
                if (string.IsNullOrEmpty(dependency.Key))
                {
                    logger.LogError($"Missing dependent definition: {dependency.Type}");
                }
                else
                {
                    var dependentAsset = assetManager.FindResolved(dependency);
                    dependentAsset?.WriteYaml(writer, assetManager, loggerFactory, indent);
                }
            }
        }

    }
}