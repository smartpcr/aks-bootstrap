using System.Threading.Tasks;
using Newtonsoft.Json.Linq;

namespace OneCS.Graph.Client
{
    public interface IServiceTreeClient
    {
        Task<JObject> GetService(string id);
    }
}