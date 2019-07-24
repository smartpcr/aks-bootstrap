using System.ComponentModel.DataAnnotations;

namespace Wizard.Assets
{
    public class AadIdentity
    {
        [Required]
        public string Name { get; set; }

        [Required, RegularExpression("user|group|app")]
        public string Type { get; set; }

        public string AppId { get; set; }

        public string ObjectId { get; set; }
    }
}