using System;

namespace Wizard.Assets
{
    [AttributeUsage(AttributeTargets.Property, AllowMultiple = false, Inherited = false)]
    public class PropertyPathAttribute : Attribute
    {
        public string JPath { get; }
        public bool IsArray { get; }

        public PropertyPathAttribute(string jpath, bool isArray = false)
        {
            JPath = jpath.Replace("/", ".");
            IsArray = isArray;
        }
    }
}