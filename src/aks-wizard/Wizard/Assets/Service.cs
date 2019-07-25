using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;

namespace Wizard.Assets
{
    [ObjectPath("code/services", true)]
    public class Services : BaseAsset, IAssetArray
    {
        public override AssetType Type => AssetType.Service;
        public override AssetKind Kind => AssetKind.Code;
        public override IList<Dependency> Dependencies { get; } = new List<Dependency>()
        {
            new Dependency(AssetType.Prodct),
            new Dependency(AssetType.ContainerRegistry),
            new Dependency(AssetType.KeyVault),
            new Dependency(AssetType.KubernetesCluster),
            new Dependency(AssetType.Dns),
            new Dependency(AssetType.PrivateFeed),
            new Dependency(AssetType.ExternalService),
            new Dependency(AssetType.VolumeShare),
            new Dependency(AssetType.KubeResources)
        };

        public override int SortOrder => 10;
        public IAsset[] Items { get; set; }
        public Type ItemType => typeof(Service);

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}services:\n");

            foreach (var service in Items.OfType<Service>())
            {
                service.WriteYaml(writer, assetManager, loggerFactory, indent + 2);
            }
        }
    }

    public class Service : BaseAsset
    {
        #region props
        public string Name { get; set; }
        [JsonProperty("type")]
        public string ServiceType { get; set; }

        public DockerImage Image { get; set; }
        public string SolutionFile { get; set; }

        public string ProjectFile { get; set; }
        public string AssemblyName { get; set; }
        public string PrivateNugetFeed { get; set; }
        public int ContainerPort { get; set; }
        public int SshPort { get; set; } = 51022;
        public bool IsFrontend { get; set; }
        public string SslCert { get; set; }
        public string LivenessCheck { get; set; }
        public string ReadinessCheck { get; set; }
        public string[] Volumes { get; set; }
        [JsonProperty("env")]
        public EnvironmentVariable[] EnvironmentVariables { get; set; }

        public string Schedule { get; set; }
        public string RestartPolicy { get; set; }
        public string ConcurrencyPolicy { get; set; }
        #endregion

        #region asset
        public override AssetType Type => AssetType.Service;
        public override AssetKind Kind => AssetKind.Code;
        public override IList<Dependency> Dependencies { get; } = new List<Dependency>()
        {
            new Dependency(AssetType.ContainerRegistry),
            new Dependency(AssetType.KeyVault),
            new Dependency(AssetType.Dns),
            new Dependency(AssetType.PrivateFeed),
            new Dependency(AssetType.ExternalService),
            new Dependency(AssetType.VolumeShare),
            new Dependency(AssetType.KubeResources)
        };

        public override int SortOrder => 10;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}- name: {Name}\n");
            spaces = "".PadLeft(indent + 2);
            writer.Write($"{spaces}type: {ServiceType}\n");
            writer.Write($"{spaces}image:\n");
            spaces = "".PadLeft(indent + 4);
            writer.Write($"{spaces}name: {Image?.Name ?? Name}\n");
            writer.Write($"{spaces}tag: {Image?.Tag ?? "{{.Values.buildNumber}}"}\n");
            spaces = "".PadLeft(indent + 2);
            if (!string.IsNullOrEmpty(SolutionFile))
            {
                writer.Write($"{spaces}solutionFile: {SolutionFile.Replace("\\", "/")}\n");
            }

            if (string.IsNullOrEmpty(ProjectFile) && !string.IsNullOrEmpty(SolutionFile))
            {
                var projName = Name.GetProjectName();
                ProjectFile = Path.Combine(Path.GetDirectoryName(SolutionFile), projName, $"{projName}.csproj");
                if (string.IsNullOrEmpty(AssemblyName))
                {
                    AssemblyName = projName;
                }
            }
            if (!string.IsNullOrEmpty(ProjectFile))
            {
                writer.Write($"{spaces}projectFile: {ProjectFile.Replace("\\", "/")}\n");
            }

            if (!string.IsNullOrEmpty(AssemblyName))
            {
                writer.Write($"{spaces}assemblyName: {AssemblyName}\n");
            }

            if (!string.IsNullOrEmpty(PrivateNugetFeed))
            {
                writer.Write($"{spaces}privateNugetFeed: {PrivateNugetFeed}\n");
            }

            if (ServiceType == "web" || ServiceType == "api")
            {
                writer.Write($"{spaces}containerPort: {ContainerPort}\n");
                writer.Write($"{spaces}sshPort: {SshPort}\n");
                if (string.IsNullOrEmpty(SslCert))
                {
                    var dns = assetManager.Get(AssetType.Dns) as Dns;
                    SslCert = dns?.SslCert;
                }
                if (!string.IsNullOrEmpty(SslCert))
                {
                    writer.Write($"{spaces}sslCert: {SslCert}\n");
                }
                writer.Write($"{spaces}isFrontEnd: {IsFrontend}\n");

                if (!string.IsNullOrEmpty(LivenessCheck))
                {
                    writer.Write($"{spaces}livenessCheck: {LivenessCheck}\n");
                }
                if (!string.IsNullOrEmpty(ReadinessCheck))
                {
                    writer.Write($"{spaces}readinessCheck: {ReadinessCheck}\n");
                }
            }

            if (ServiceType == "job")
            {
                writer.Write($"{spaces}schedule: {Schedule ?? "*/1 * * * *"}\n");
                writer.Write($"{spaces}restartPolicy: {RestartPolicy ?? "Never"}\n");
                writer.Write($"{spaces}concurrencyPolicy: {ConcurrencyPolicy ?? "Forbid"}\n");
            }

            if (Volumes?.Any() == true)
            {
                writer.Write($"{spaces}volumes:\n");
                spaces = "".PadLeft(indent + 4);
                foreach (var volume in Volumes)
                {
                    writer.Write($"{spaces}- name: {volume}\n");
                }
            }
            spaces = "".PadLeft(indent + 4);

            if (EnvironmentVariables?.Any() == true)
            {
                writer.Write($"{spaces}env:\n");
                spaces = "".PadLeft(indent + 4);
                foreach (var envVar in EnvironmentVariables)
                {
                    writer.Write($"{spaces}- name: {envVar.Name}\n");
                    writer.Write($"{spaces}  value: {envVar.Value}\n");
                }
            }
        }
        #endregion
    }

    public class DockerImage
    {
        public string Name { get; set; }
        public string Tag { get; set; }
    }

    public class EnvironmentVariable
    {
        public string Name { get; set; }
        public string Value { get; set; }
    }

    public static class ProjectFileExtension
    {
        public static string GetProjectName(this string serviceName)
        {
            var parts = serviceName.Split(new[] {"-"}, StringSplitOptions.None);
            List<string> tokens = new List<string>();
            foreach (var part in parts)
            {
                var token = part.Substring(0, 1).ToUpper() + part.Substring(1);
                tokens.Add(token);
            }

            return string.Join(".", tokens);
        }
    }
}