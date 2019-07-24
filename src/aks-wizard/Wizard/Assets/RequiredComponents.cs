using System.Collections.Generic;
using System.IO;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    public class RequiredComponents: BaseAsset
    {
        #region props
        [PropertyPath("global/components/terraform")]
        public bool Terraform { get; set; }

        [PropertyPath("global/components/aks")]
        public bool Aks { get; set; }

        [PropertyPath("global/components/acr")]
        public bool Acr { get; set; }

        [PropertyPath("global/components/serviceBus")]
        public bool ServiceBus { get; set; }

        [PropertyPath("global/components/appInsights")]
        public bool AppInsights { get; set; }

        [PropertyPath("global/components/dns")]
        public bool Dns { get; set; }

        [PropertyPath("global/components/traffic")]
        public bool Traffic { get; set; }

        [PropertyPath("global/components/redis")]
        public bool Redis { get; set; }

        [PropertyPath("global/components/cosmosDb")]
        public CosmosDbComponent CosmosDb { get; set; }
        #endregion

        #region override
        public override AssetType Type => AssetType.RequiredComponents;
        public override IList<Dependency> Dependencies { get; } = new List<Dependency>();
        public override int SortOrder => 0;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}components:\n");
            spaces = "".PadLeft(indent + 2);
            writer.Write($"{spaces}terraform: {Terraform}\n");
            writer.Write($"{spaces}aks: {Aks}\n");
            writer.Write($"{spaces}acr: {Acr}\n");
            writer.Write($"{spaces}appInsights: {AppInsights}\n");
            writer.Write($"{spaces}dns: {Dns}\n");
            writer.Write($"{spaces}traffic: {Traffic}\n");
            writer.Write($"{spaces}redis: {Redis}\n");
            writer.Write($"{spaces}cosmosDb:\n");
            spaces = "".PadLeft(indent + 4);
            writer.Write($"{spaces}docDb: {CosmosDb?.DocDb == true}\n");
            writer.Write($"{spaces}mongoDb: {CosmosDb?.MongoDb == true}\n");
            writer.Write($"{spaces}mongoDb: {CosmosDb?.GraphDb == true}\n");
        }

        #endregion
    }

    public class CosmosDbComponent
    {
        public bool DocDb { get; set; }
        public bool MongoDb { get; set; }
        public bool GraphDb { get; set; }
    }
}