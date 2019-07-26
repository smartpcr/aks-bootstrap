namespace Common.KeyVault
{
    public class KeyVaultSettings
    {
        public string Name { get; set; }
        public string ClientId { get; set; }

        /// <summary>
        /// outside cluster, use mounted cert file, otherwise, use MSI (pod identity)
        /// </summary>
        public string ClientCertFile { get; set; }
        public string VaultUrl => $"https://{Name}.vault.azure.net";
    }
}