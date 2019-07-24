using System;

namespace Wizard.Assets
{
    public class Dependency
    {
        public AssetType Type { get; }
        public string Key { get; set; }
        public bool IsOptional { get; } = false;
        public bool CanHaveMany { get; } = false;
        public bool AllowOverwrite { get; set; } = false;

        public Dependency(AssetType type, string key = null)
        {
            Type = type;
            Key = key;
        }
    }
}