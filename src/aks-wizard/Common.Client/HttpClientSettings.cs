using Common.Auth;

namespace Common.Client
{
    public class HttpClientSettings
    {
        public string EndpointUrl { get; set; }
        public bool AllowAnonymousAccess { get; set; } = false;
        public int TimeoutInSeconds { get; set; } = 30;
        public int MaxRetryCount { get; set; } = 3;
        public int CircuitBreakMaxRetries { get; set; } = 10;
        public int CircuitBreakBackoffInSeconds { get; set; } = 30;
    }

}