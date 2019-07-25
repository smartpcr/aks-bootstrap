using System;
using System.Collections.Generic;
using System.IO;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    public interface IAsset
    {
        string Key { get; }
        AssetType Type { get; }
        AssetKind Kind { get; }
        IList<Dependency> Dependencies { get; }
        int SortOrder { get; }

        void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory, int indent = 0);
    }

    public interface IAssetArray
    {
        IAsset[] Items { get; set; }
        Type ItemType { get; }
    }

    public enum AssetType
    {
        Global,
        RequiredComponents,
        Subscription,
        ResourceGroup,
        KeyVault,
        CosmosDb,
        Terraform,
        ContainerRegistry,
        KubernetesCluster,
        AppInsights,
        ServiceBus,
        Dns,
        Prodct,
        PrivateFeed,
        VolumeShare,
        KubeResources,
        Service,
        Solution,
        Project,
        Web,
        Api,
        Job,
        ExternalService,
    }

    public enum AssetKind
    {
        Infra,
        Code,
        Shared
    }
}