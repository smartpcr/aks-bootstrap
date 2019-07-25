using System.Collections.Generic;
using System.IO;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    [ObjectPath("azure/acr")]
    public class ContainerRegistry:BaseAsset
    {
        #region MyRegion
        public string Name { get; set; }
        public string PasswordSecretName { get; set; }
        public string Email { get; set; }
        public string ResourceGroup { get; set; }
        #endregion

        #region asset override

        public override AssetType Type => AssetType.ContainerRegistry;
        public override AssetKind Kind => AssetKind.Shared;

        public override IList<Dependency> Dependencies { get; } = new List<Dependency>()
        {
            new Dependency(AssetType.Global)
        };

        public override int SortOrder => 3;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}acr:\n");
            spaces = "".PadLeft(indent + 2);
            writer.Write($"{spaces}name: {Name}\n");
            writer.Write($"{spaces}passwordSecretName: {PasswordSecretName}\n");
            writer.Write($"{spaces}email: {Email}\n");

            var resourceGroup = ResourceGroup ?? assetManager.GetResourceGroup()?.Name;
            if (!string.IsNullOrEmpty(resourceGroup))
            {
                writer.Write($"{spaces}resourceGroup: {resourceGroup}\n");
            }
        }

        #endregion
    }
}