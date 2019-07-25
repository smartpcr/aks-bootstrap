using System.ComponentModel.DataAnnotations;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    public interface IAzureAssetValidator : IValidatableObject
    {
        (bool IsValid, string Error) ValidateAzureAsset(AssetManager assetManager, ILoggerFactory loggerFactory);
        bool Fix(AssetManager assetManager, ILoggerFactory loggerFactory);
    }
}