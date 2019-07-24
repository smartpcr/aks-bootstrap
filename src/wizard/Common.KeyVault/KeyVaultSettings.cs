namespace Common.KeyVault
{
    public class KeyVaultSettings
    {
        public string Name { get; set; }
        public string ClientId { get; set; }
        public string ClientCertFile { get; set; }
        public string VaultUrl => $"https://{Name}.vault.azure.net";
    }
}