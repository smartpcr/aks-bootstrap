using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    [ObjectPath("code/privateFeeds", true)]
    public class PrivateFeeds: BaseAsset, IAssetArray
    {
        #region override asset
        public override AssetType Type => AssetType.PrivateFeed;
        public override AssetKind Kind => AssetKind.Code;
        public override IList<Dependency> Dependencies { get; } = new List<Dependency>();
        public override int SortOrder => 4;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}nugetFeeds:\n");

            foreach (var feed in Items.OfType<PrivateFeed>())
            {
                feed.WriteYaml(writer, assetManager, loggerFactory, indent + 2);
            }
        }
        #endregion

        #region override array
        public IAsset[] Items { get; set; }
        public Type ItemType => typeof(PrivateFeed);
        #endregion
    }

    public class PrivateFeed : BaseAsset
    {
        #region props
        public string Name { get; set; }
        public string Url { get; set; }
        public string PasswordFromEnvironment { get; set; }
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
            writer.Write($"{spaces}url: {Url}\n");
            writer.Write($"{spaces}passwordFromEnvironment: {PasswordFromEnvironment}\n");
        }
        #endregion

    }
}