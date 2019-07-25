using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.IO;
using Microsoft.Extensions.Logging;
using Wizard.AzureResources;

namespace Wizard.Assets
{
    [ObjectPath("azure/kv")]
    public class KeyVault : BaseAsset, IAzureAssetValidator
    {
        [MaxLength(25), MinLength(3)] public string Name { get; set; }

        #region override

        public override AssetType Type => AssetType.KeyVault;

        public override IList<Dependency> Dependencies { get; } = new List<Dependency>()
        {
            new Dependency(AssetType.ResourceGroup)
        };

        public override int SortOrder { get; } = 2;

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory,
            int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}kv:\n");
            spaces = "".PadLeft(indent + 2);
            writer.Write($"{spaces}name: {Name}\n");
            base.WriteYaml(writer, assetManager, loggerFactory, indent + 2);
        }

        #endregion

        /// <summary>
        /// make sure vault name is unique globally
        /// </summary>
        /// <returns></returns>
        /// <exception cref="NotImplementedException"></exception>
        public (bool IsValid, string Error) ValidateAzureAsset(AssetManager assetManager, ILoggerFactory loggerFactory)
        {
            var subscription = assetManager.Get(AssetType.Subscription) as AzureSubscription;
            if (subscription == null)
            {
                throw new Exception("Missing dependency: AzureSubscription");
            }

            /*var resourceType = "Microsoft.KeyVault";
            var azureRestClient =
                new AzureRestClient(subscription.SubscriptionId, loggerFactory.CreateLogger<AzureRestClient>());
            var isUnique = azureRestClient.CheckNameIsUnique(resourceType, Name).GetAwaiter().GetResult();
            if (!isUnique)
            {
                // Get tags and verify that I owns this asset
            }*/

            return (true, null);
        }

        public bool Fix(AssetManager assetManager, ILoggerFactory loggerFactory)
        {
            int maxRetries = 5;
            int retryCount = 0;
            var validationResult = ValidateAzureAsset(assetManager, loggerFactory);
            while (!validationResult.IsValid && retryCount < maxRetries)
            {
                Console.WriteLine("Enter vault name:");
                Name = Console.ReadLine();
                validationResult = ValidateAzureAsset(assetManager, loggerFactory);
                retryCount++;
            }

            return validationResult.IsValid;
        }

        public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
        {
            return new List<ValidationResult>();
        }
    }
}