using System.Net.Http;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace Wizard.AzureResources
{
    public class AzureRestClient
    {
        private readonly string _subscriptionId;
        private readonly ILogger<AzureRestClient> _logger;
        private readonly HttpClient _httpClient;

        public AzureRestClient(string subscriptionId, ILogger<AzureRestClient> logger)
        {
            _httpClient = new HttpClient();
            _subscriptionId = subscriptionId;
            _logger = logger;
        }

        public async Task<bool> CheckNameIsUnique(string resourceType, string resourceName)
        {
            var url =
                $"https://management.azure.com/subscriptions/{_subscriptionId}/providers/Microsoft.Search/checkNameAvailability?api-version=2015-08-19";
            var jsonBody = JsonConvert.SerializeObject(new
            {
                name = resourceName,
                type = resourceType
            });
            var response = await _httpClient.PostAsync(url, new StringContent(jsonBody));
            var responseJson = JToken.Parse(await response.Content.ReadAsStringAsync());
            var isAvailable = responseJson.Value<bool>("nameAvailable");
            if (!isAvailable)
            {
                _logger.LogError(responseJson.ToString());
            }

            return isAvailable;
        }
    }
}