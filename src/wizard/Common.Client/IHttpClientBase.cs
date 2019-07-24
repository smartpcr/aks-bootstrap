using System.Net.Http;

namespace Common.Client
{
    /// <summary>
    ///
    /// </summary>
    public interface IHttpClientBase
    {
        HttpClient Client { get; }
    }

    public class HttpClientBase : IHttpClientBase
    {
        public HttpClientBase(HttpClient client)
        {
            Client = client;
        }

        public HttpClient Client { get; }
    }
}