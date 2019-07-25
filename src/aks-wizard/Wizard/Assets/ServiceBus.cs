using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.IO;
using System.Linq;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    [ObjectPath("azure/serviceBus")]
    public class ServiceBus : BaseAsset
    {
        #region props
        [Required]
        public string Name { get; set; }
        public string ResourceGroup { get; set; }
        public string[] Queues { get; set; }
        public string[] Topics { get; set; }

        #endregion

        public override AssetType Type => AssetType.ServiceBus;
        public override IList<Dependency> Dependencies { get; } = new List<Dependency>()
        {
            new Dependency(AssetType.Global)
        };

        public override int SortOrder => 7;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}servicebus:\n");

            spaces = "".PadLeft(indent + 2);
            writer.Write($"{spaces}name: {Name}\n");
            var resourceGroup = ResourceGroup ?? assetManager.GetResourceGroup()?.Name;
            if (!string.IsNullOrEmpty(resourceGroup))
            {
                writer.Write($"{spaces}resourceGroup: {resourceGroup}\n");
            }

            if (Queues?.Any()==true)
            {
                writer.Write($"{spaces}queues:\n");
                foreach (var queue in Queues)
                {
                    spaces = "".PadLeft(indent + 4);
                    writer.Write($"{spaces}- {queue}\n");
                }
            }
            if (Topics?.Any()==true)
            {
                writer.Write($"{spaces}topics:\n");
                foreach (var topic in Topics)
                {
                    spaces = "".PadLeft(indent + 4);
                    writer.Write($"{spaces}- {topic}\n");
                }
            }

        }
    }
}