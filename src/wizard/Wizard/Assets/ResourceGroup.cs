using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.IO;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    public class ResourceGroup : BaseAsset, IUniqueValidator
    {
        [Required, PropertyPath("global/resourceGroup")]
        public string Name { get; set; }

        [Required, PropertyPath("global/location")]
        public string Location { get; set; }

        public override AssetType Type => AssetType.ResourceGroup;

        public override IList<Dependency> Dependencies { get; } = new List<Dependency>()
        {
            new Dependency(AssetType.Subscription)
        };

        public override int SortOrder { get; } = 0;


        public bool Validate()
        {
            return true;
        }

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory,
            int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}resourceGroup: {Name}\n");
            writer.Write($"{spaces}location: {Location}\n");
        }
    }
}