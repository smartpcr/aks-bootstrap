using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    public class AssetValidator
    {
        private readonly AssetManager _assetManager;
        private readonly ILoggerFactory _loggerFactory;
        private readonly ILogger<AssetValidator> _logger;

        public AssetValidator(AssetManager assetManager, ILoggerFactory loggerFactory)
        {
            _assetManager = assetManager;
            _loggerFactory = loggerFactory;
            _logger = _loggerFactory.CreateLogger<AssetValidator>();
        }

        public void TryToValidateAssets(IEnumerable<IAsset> assets)
        {
            foreach (var asset in assets)
            {
                if (asset is IAzureAssetValidator validator)
                {
                    var modelValidationResults = new List<ValidationResult>();
                    if (!Validator.TryValidateObject(asset, new ValidationContext(asset), modelValidationResults))
                    {
                        foreach (var result in modelValidationResults)
                        {
                            var errorMessage = $"Invalid asset {asset.Type}: {result.ErrorMessage}";
                            _logger.LogError(errorMessage);
                        }
                    }

                    var validationResult = validator.ValidateAzureAsset(_assetManager, _loggerFactory);
                    if (!validationResult.IsValid)
                    {
                        var errorMessage = $"Invalid asset {asset.Type}: {validationResult.Error}";
                        _logger.LogError(errorMessage);

                        bool isFixed = validator.Fix(_assetManager, _loggerFactory);
                        if (!isFixed)
                        {
                            throw new Exception($"Invalid asset {asset.Type}: {asset.Key}");
                        }
                    }
                }
            }
        }
    }
}