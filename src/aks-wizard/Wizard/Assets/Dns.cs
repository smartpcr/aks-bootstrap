using System.Collections.Generic;
using System.IO;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    [ObjectPath("azure/dns")]
    public class Dns : BaseAsset
    {
        #region props

        public string Name { get; set; }
        public string Domain { get; set; }
        public string SslCert { get; set; }
        public string DomainOwnerEmail { get; set; }
        public string ResourceGroup { get; set; }

        #endregion

        #region override
        public override AssetType Type => AssetType.Dns;
        public override IList<Dependency> Dependencies { get; } = new List<Dependency>()
        {
            new Dependency(AssetType.Global)
        };

        public override int SortOrder => 8;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}dns:\n");

            spaces = "".PadLeft(indent + 2);
            writer.Write($"{spaces}name: {Name}\n");
            writer.Write($"{spaces}domain: {Domain}\n");
            writer.Write($"{spaces}sslCert: {SslCert}\n");
            writer.Write($"{spaces}domainOwnerEmail: {DomainOwnerEmail}\n");

            var resourceGroup = ResourceGroup ?? assetManager.GetResourceGroup()?.Name;
            if (!string.IsNullOrEmpty(resourceGroup))
            {
                writer.Write($"{spaces}resourceGroup: {resourceGroup}\n");
            }
        }
        #endregion
    }
}