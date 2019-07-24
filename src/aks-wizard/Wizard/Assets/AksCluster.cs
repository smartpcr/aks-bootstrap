using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    [ObjectPath("azure/aks")]
    public class AksCluster : BaseAsset
    {
        #region MyRegion

        public string ClusterName { get; set; }
        public string DnsPrefix { get; set; }
        public string Version { get; set; }
        public int NodeCount { get; set; }
        public string VmSize { get; set; }
        public string AksOwnerAadUpn { get; set; }
        public AadIdentity[] Readers { get; set; }
        public AadIdentity[] Contributors { get; set; }
        public AadIdentity[] Owners { get; set; }
        public bool UseDevSpaces { get; set; }
        public bool UseTerraform { get; set; }
        public bool UseIstio { get; set; }
        public bool UseCertManager { get; set; }
        public string[] KeyVaultAccess { get; set; }
        public string[] Metrics { get; set; }
        public string[] Logging { get; set; }
        public string[] Tracing { get; set; }
        public string[] Ingress { get; set; }
        public AksCert[] Certs { get; set; }
        public AksSecrets Secrets { get; set; }

        #endregion

        public override AssetType Type => AssetType.KubernetesCluster;

        public override IList<Dependency> Dependencies { get; } = new List<Dependency>()
        {
            new Dependency(AssetType.Global) {AllowOverwrite = true},
            new Dependency(AssetType.ContainerRegistry)
        };

        public override int SortOrder => 5;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory,
            int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}aks:\n");
            spaces = "".PadLeft(indent + 2);
            writer.Write($"{spaces}clusterName: {ClusterName}\n");
            writer.Write($"{spaces}dnsPrefix: {DnsPrefix}\n");
            writer.Write($"{spaces}version: {Version}\n");
            writer.Write($"{spaces}vmSize: {VmSize}\n");
            writer.Write($"{spaces}nodeCount: {NodeCount}\n");
            writer.Write($"{spaces}ownerUpn: {AksOwnerAadUpn}\n");

            writer.Write($"{spaces}access:\n");

            if (Readers?.Any() == true)
            {
                spaces = "".PadLeft(indent + 4);
                writer.Write($"{spaces}readers:");

                spaces = "".PadLeft(indent + 6);
                foreach (var aadIdentity in Readers)
                {
                    writer.Write($"{spaces}name: {aadIdentity.Name}\n");
                    writer.Write($"{spaces}type: {aadIdentity.Type}\n");
                }
            }

            if (Contributors?.Any() == true)
            {
                spaces = "".PadLeft(indent + 4);
                writer.Write($"{spaces}contributors:");

                spaces = "".PadLeft(indent + 6);
                foreach (var aadIdentity in Contributors)
                {
                    writer.Write($"{spaces}name: {aadIdentity.Name}\n");
                    writer.Write($"{spaces}type: {aadIdentity.Type}\n");
                }
            }

            if (Owners?.Any() == true)
            {
                spaces = "".PadLeft(indent + 4);
                writer.Write($"{spaces}owners:");

                spaces = "".PadLeft(indent + 6);
                foreach (var aadIdentity in Owners)
                {
                    writer.Write($"{spaces}name: {aadIdentity.Name}\n");
                    writer.Write($"{spaces}type: {aadIdentity.Type}\n");
                }
            }

            spaces = "".PadLeft(indent + 2);
            writer.Write($"{spaces}useDevSpaces: {UseDevSpaces}\n");
            writer.Write($"{spaces}useTerraform: {UseTerraform}\n");
            writer.Write($"{spaces}useIstio: {UseIstio}\n");
            writer.Write($"{spaces}useCertManager: {UseCertManager}\n");

            if (KeyVaultAccess?.Any() == true)
            {
                spaces = "".PadLeft(indent + 2);
                writer.Write($"{spaces}keyVaultAccess:\n");

                foreach (var option in KeyVaultAccess)
                {
                    spaces = "".PadLeft(indent + 4);
                    writer.Write($"{spaces}- {option}\n");
                }
            }

            if (Metrics?.Any() == true)
            {
                spaces = "".PadLeft(indent + 2);
                writer.Write($"{spaces}metrics:\n");

                foreach (var option in Metrics)
                {
                    spaces = "".PadLeft(indent + 4);
                    writer.Write($"{spaces}- {option}\n");
                }
            }

            if (Logging?.Any() == true)
            {
                spaces = "".PadLeft(indent + 2);
                writer.Write($"{spaces}logging:\n");

                foreach (var option in Logging)
                {
                    spaces = "".PadLeft(indent + 4);
                    writer.Write($"{spaces}- {option}\n");
                }
            }

            if (Tracing?.Any() == true)
            {
                spaces = "".PadLeft(indent + 2);
                writer.Write($"{spaces}tracing:\n");

                foreach (var option in Tracing)
                {
                    spaces = "".PadLeft(indent + 4);
                    writer.Write($"{spaces}- {option}\n");
                }
            }

            if (Ingress?.Any() == true)
            {
                spaces = "".PadLeft(indent + 2);
                writer.Write($"{spaces}ingress:\n");

                foreach (var option in Ingress)
                {
                    spaces = "".PadLeft(indent + 4);
                    writer.Write($"{spaces}- {option}\n");
                }
            }

            if (Certs?.Any() == true)
            {
                spaces = "".PadLeft(indent + 2);
                writer.Write($"{spaces}certs:\n");

                foreach (var cert in Certs)
                {
                    spaces = "".PadLeft(indent + 4);
                    writer.Write($"{spaces}- name: {cert.Name}\n");
                    if (!string.IsNullOrEmpty(cert.Type))
                    {
                        writer.Write($"{spaces}  type: {cert.Type}\n");
                    }
                }
            }

            if (Secrets != null)
            {
                spaces = "".PadLeft(indent + 2);
                writer.Write($"{spaces}secrets:\n");

                spaces = "".PadLeft(indent + 4);
                writer.Write($"{spaces}addContainerRegistryAccess: {Secrets.AddContainerRegistryAccess}\n");
                writer.Write($"{spaces}addKeyVaultAccess: {Secrets.AddKeyVaultAccess}\n");
                writer.Write($"{spaces}addAppInsightsKey: {Secrets.AddAppInsightsKey}\n");
            }
        }
    }

    public class AksSecrets
    {
        public bool AddContainerRegistryAccess { get; set; }
        public bool AddKeyVaultAccess { get; set; }
        public bool AddAppInsightsKey { get; set; }
    }

    public class AksCert
    {
        public string Name { get; set; }
        public string Type { get; set; }
    }
}