using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.IO;
using Microsoft.Extensions.Logging;

namespace Wizard.Assets
{
    [ObjectPath("azure/kv")]
    public class KeyVault : BaseAsset, IUniqueValidator
    {
        [MaxLength(25), MinLength(3)]
        public string Name { get; set; }

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
        public bool Validate()
        {
            // TODO: implement using rest api
            return true;
        }
    }
}