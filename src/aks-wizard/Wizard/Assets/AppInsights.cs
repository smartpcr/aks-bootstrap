using System.Collections.Generic;
using System.IO;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    [ObjectPath("azure/appInsights")]
    public class AppInsights : BaseAsset
    {
        #region props

        public string Name { get; set; }

        public string ResourceGroup { get; set; }

        #endregion

        #region asset override

        public override AssetType Type => AssetType.AppInsights;

        public override IList<Dependency> Dependencies { get; } = new List<Dependency>()
        {
            new Dependency(AssetType.Global)
        };

        public override int SortOrder => 4;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory,
            int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}appInsights:\n");
            spaces = "".PadLeft(indent + 2);
            writer.Write($"{spaces}name: {Name}\n");

            var resourceGroup = ResourceGroup ?? assetManager.GetResourceGroup()?.Name;
            if (!string.IsNullOrEmpty(resourceGroup))
            {
                writer.Write($"{spaces}resourceGroup: {resourceGroup}\n");
            }
        }

        #endregion
    }
}