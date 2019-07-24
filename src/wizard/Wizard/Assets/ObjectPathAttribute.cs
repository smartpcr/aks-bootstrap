using System;

namespace Wizard.Assets
{
    [AttributeUsage(AttributeTargets.Class)]
    public class ObjectPathAttribute : Attribute
    {
        public bool AllowMultiple { get; }
        public string JPath { get; }

        public ObjectPathAttribute(string jpath, bool allowMultiple = false)
        {
            JPath = jpath.Replace("/", ".");
            AllowMultiple = allowMultiple;
        }
    }
}