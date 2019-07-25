using System.Collections.Generic;
using System.IO;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    [ObjectPath("code/resources")]
    public class KubeServiceResources : BaseAsset
    {
        public ResourceClaims Api { get; set; }
        public ResourceClaims Job { get; set; }
        public ResourceClaims Web { get; set; }

        #region override

        public override AssetType Type => AssetType.KubeResources;
        public override AssetKind Kind => AssetKind.Code;
        public override IList<Dependency> Dependencies { get; } = new List<Dependency>();
        public override int SortOrder => 1;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}resources:\n");
            Api?.WriteYaml(writer, assetManager, loggerFactory, "api", indent + 2);
            Job?.WriteYaml(writer, assetManager, loggerFactory, "job", indent + 2);
            Web?.WriteYaml(writer, assetManager, loggerFactory, "web", indent + 2);
        }
        #endregion
    }

    public class ResourceClaims
    {
        public ResourceClaim Requests { get; set; }
        public ResourceClaim Limits { get; set; }

        public void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, string name, int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}- name: {name}\n");
            Requests?.WriteYaml(writer, assetManager, loggerFactory, "requests", indent + 2);
            Limits?.WriteYaml(writer, assetManager, loggerFactory, "limits", indent + 2);
        }
    }

    public class ResourceClaim
    {
        public string Memory { get; set; }
        public string Cpu { get; set; }

        public void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, string name, int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}{name}\n");
            spaces = "".PadLeft(indent + 2);
            writer.Write($"{spaces}memory: {Memory}\n");
            writer.Write($"{spaces}cpu: {Cpu}\n");
        }
    }

}