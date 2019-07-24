using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.IO;
using System.Linq;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    [ObjectPath("azure/cosmosDbs", true)]
    public class CosmosDbs : BaseAsset, IAssetArray
    {
        public IAsset[] Items { get; set; } = new IAsset[0];
        public Type ItemType => typeof(CosmosDb);
        public override AssetType Type => AssetType.CosmosDb;
        public override IList<Dependency> Dependencies { get; } = new List<Dependency>()
        {
            new Dependency(AssetType.Global)
        };

        public override int SortOrder => 4;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}cosmosdb:\n");

            foreach (var cosmosDb in Items.OfType<CosmosDb>())
            {
                spaces = "".PadLeft(indent + 2);
                writer.Write($"{spaces}- name: {cosmosDb.Account}:\n");
                cosmosDb.WriteYaml(writer, assetManager, loggerFactory, indent + 4);
            }
        }
    }

    public class CosmosDb : BaseAsset
    {
        [MaxLength(25), MinLength(3)]
        public string Account { get; set; }

        [Required, RegularExpression("SQL|Gremlin")]
        public string Api { get; set; }

        public string Db { get; set; }

        public CosmosDbCollection[] Collections { get; set; }

        public override AssetType Type => AssetType.CosmosDb;
        public override IList<Dependency> Dependencies { get; } = new List<Dependency>()
        {
            new Dependency(AssetType.Global)
        };

        public override int SortOrder => 4;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, int indent = 0)
        {
            var spaces = "".PadLeft(indent);

            writer.Write($"{spaces}account: {Account}\n");
            writer.Write($"{spaces}api: {Api}\n");
            writer.Write($"{spaces}db: {Db}\n");

            writer.Write($"{spaces}collections:\n");
            foreach (var dbCollection in Collections)
            {
                spaces = "".PadLeft(indent + 2);
                writer.Write($"{spaces}- name: {dbCollection.Name}\n");
                if (!string.IsNullOrEmpty(dbCollection.Partition))
                {
                    writer.Write($"{spaces}  partition: {dbCollection.Partition}\n");
                }

                writer.Write($"{spaces}  throughput: {dbCollection.Throughput}\n");
            }
        }
    }

    public class CosmosDbCollection
    {
        public string Name { get; set; }
        public string Partition { get; set; }
        public int Throughput { get; set; }
    }
}