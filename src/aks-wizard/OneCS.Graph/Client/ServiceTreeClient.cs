using System.Net.Http;
using System.Threading.Tasks;
using Common.Client;
using Common.Metrics;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;

namespace OneCS.Graph.Client
{
    public class ServiceTreeClient: HttpClientBase, IServiceTreeClient
    {
        public ServiceTreeClient(
            HttpClient client,
            ILogger<ServiceTreeClient> logger,
            ITelemetryClient telemetry) : base(client)
        {
        }

        public Task<JObject> GetService(string id)
        {
            throw new System.NotImplementedException();
        }
    }
}