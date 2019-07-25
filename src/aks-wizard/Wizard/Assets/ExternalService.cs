using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    [ObjectPath("code/external", true)]
    public class ExternalServices : BaseAsset, IAssetArray
    {
        #region override asset
        public override AssetType Type => AssetType.ExternalService;
        public override AssetKind Kind => AssetKind.Code;
        public override IList<Dependency> Dependencies { get; } = new List<Dependency>();
        public override int SortOrder => 1;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}externalServices:\n");

            foreach (var externalService in Items.OfType<ExternalService>())
            {
                externalService.WriteYaml(writer, assetManager, loggerFactory, indent + 2);
            }
        }
        #endregion

        #region override array
        public IAsset[] Items { get; set; }
        public Type ItemType => typeof(ExternalService);
        #endregion
    }

    public class ExternalService : BaseAsset
    {
        #region props
        public string Name { get; set; }
        public string Endpoint { get; set; }
        public string ResourceId { get; set; }
        #endregion

        #region override asset
        public override AssetType Type => AssetType.ExternalService;
        public override AssetKind Kind => AssetKind.Code;
        public override IList<Dependency> Dependencies { get; } = new List<Dependency>();
        public override int SortOrder => 1;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}- name: {Name}:\n");
            spaces = "".PadLeft(indent + 2);
            writer.Write($"{spaces}endpoint: {Endpoint}\n");
            if (!string.IsNullOrEmpty(ResourceId))
            {
                writer.Write($"{spaces}resourceId: {ResourceId}\n");
            }
        }
        #endregion
    }
}