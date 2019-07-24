using System;

namespace Common.Auth
{
    public class AadAppSettings
    {
        /// <summary>
        /// aad directory tenant, used to construct authority for login url
        /// </summary>
        public string TenantId { get; set; }

        /// <summary>
        /// aad app id
        /// </summary>
        public string ClientId { get; set; }

        /// <summary>
        /// key vault secret for aad app client secret
        /// </summary>
        public string ClientSecret { get; set; }

        /// <summary>
        /// key vault secret for aad cert
        /// </summary>
        public string ClientCertName { get; set; }

        /// <summary>
        /// readonly aad authority
        /// </summary>
        public Uri Authority => new Uri($"https://login.microsoftonline.com/{TenantId}/v2.0");

        /// <summary>
        /// requested resources to access
        /// </summary>
        public string[] Scopes { get; set; }

        /// <summary>
        /// either none (anonymous), user (interactive, for browser) and api (service principal)
        /// </summary>
        public AuthTokenType TokenType { get; set; }
    }

    public enum AuthTokenType
    {
        None,
        AadApp,
        AadUser
    }

    public enum AppType
    {
        Api,
        Web,
        Job
    }
}