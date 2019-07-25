using System.Collections.Generic;
using System.IO;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    [ObjectPath("azure/terraform")]
    public class Terraform:BaseAsset
    {
        #region props

        public string ResourceGroup { get; set; }
        public string ServicePrincipal { get; set; }
        public string StateStorageAccountName { get; set; }

        #endregion

        #region asset override
        public override AssetType Type => AssetType.Terraform;
        public override IList<Dependency> Dependencies { get; } = new List<Dependency>()
        {
            new Dependency(AssetType.Global)
        };

        public override int SortOrder => 3;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}terraform:\n");

            spaces = "".PadLeft(indent + 2);
            var resourceGroup = ResourceGroup ?? assetManager.GetResourceGroup()?.Name;
            if (!string.IsNullOrEmpty(resourceGroup))
            {
                writer.Write($"{spaces}resourceGroup: {resourceGroup}\n");
            }
            if (!string.IsNullOrEmpty(ServicePrincipal))
            {
                writer.Write($"{spaces}servicePrincipal: {ServicePrincipal}\n");
            }
            if (!string.IsNullOrEmpty(StateStorageAccountName))
            {
                writer.Write($"{spaces}stateStorageAccountName: {StateStorageAccountName}\n");
            }
        }

        #endregion
    }
}