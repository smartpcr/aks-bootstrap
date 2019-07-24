using System.Collections.Generic;
using System.IO;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    public class Product : BaseAsset
    {
        [PropertyPath("global/productName")]
        public string Name { get; set; }


        public override AssetType Type => AssetType.Prodct;
        public override IList<Dependency> Dependencies { get; } = new List<Dependency>();

        public override int SortOrder { get; }= 0;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}productName: {Name}\n");
        }
    }
}