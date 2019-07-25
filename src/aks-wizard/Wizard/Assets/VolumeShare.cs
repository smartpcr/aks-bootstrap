using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    [ObjectPath("code/volumeShares", true)]
    public class VolumeShares : BaseAsset, IAssetArray
    {
        #region override asset
        public override AssetType Type => AssetType.VolumeShare;
        public override AssetKind Kind => AssetKind.Code;
        public override IList<Dependency> Dependencies { get; } = new List<Dependency>();
        public override int SortOrder => 1;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}shares:\n");

            foreach (var share in Items.OfType<VolumeShare>())
            {
                share.WriteYaml(writer, assetManager, loggerFactory, indent + 2);
            }
        }
        #endregion

        #region override array
        public IAsset[] Items { get; set; }
        public Type ItemType => typeof(VolumeShare);
        #endregion
    }

    public class VolumeShare: BaseAsset
    {
        #region props
        public string Name { get; set; }
        public string HostPath { get; set; }
        public string ContainerPath { get; set; }
        public bool LocalOnly { get; set; } = true;
        #endregion

        #region override asset
        public override AssetType Type => AssetType.PrivateFeed;
        public override AssetKind Kind => AssetKind.Code;
        public override IList<Dependency> Dependencies { get; } = new List<Dependency>();
        public override int SortOrder => 1;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}- name: {Name}:\n");
            spaces = "".PadLeft(indent + 2);
            writer.Write($"{spaces}hostPath: {HostPath}\n");
            writer.Write($"{spaces}containerPath: {ContainerPath}\n");
            writer.Write($"{spaces}localOnly: {LocalOnly}\n");
        }
        #endregion

    }
}