using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.IO;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    public class ResourceGroup : BaseAsset, IAzureAssetValidator
    {
        [Required, PropertyPath("global/resourceGroup")]
        public string Name { get; set; }

        [Required, PropertyPath("global/location")]
        public string Location { get; set; }

        public override AssetType Type => AssetType.ResourceGroup;

        public override IList<Dependency> Dependencies { get; } = new List<Dependency>()
        {
            new Dependency(AssetType.Subscription)
        };

        public override int SortOrder { get; } = 0;


        public (bool IsValid, string Error) ValidateAzureAsset(AssetManager assetManager, ILoggerFactory loggerFactory)
        {
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

        public override void WriteYaml(StreamWriter writer, AssetManager assetManager, ILoggerFactory loggerFactory,
            int indent = 0)
        {
            var spaces = "".PadLeft(indent);
            writer.Write($"{spaces}resourceGroup: {Name}\n");
            writer.Write($"{spaces}location: {Location}\n");
        }

        public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
        {
            return new List<ValidationResult>();
        }
    }
}