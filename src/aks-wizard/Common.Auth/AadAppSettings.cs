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
        /// client secret for aad app
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