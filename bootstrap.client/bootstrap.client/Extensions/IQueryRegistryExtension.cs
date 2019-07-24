using bootstrap.client.Data;
using bootstrap.client.Interfaces;
using Newtonsoft.Json.Linq;
using System.Linq;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;
using Newtonsoft.Json;
using System.IO;

namespace bootstrap.client.Extensions
{
    public static class IQueryRegistryExtension
    {
        public static async Task WriteAync(this IQueryRegistry registry, string fileName)
        {
            var values = new JObject();
            var roots = registry.GetRootQueries();
            foreach(var root in roots)
            {
                WriteQueryResponse(root, values, registry);
            }
            using (StreamWriter file = File.CreateText(fileName))
            {
                using (JsonTextWriter writer = new JsonTextWriter(file))
                {
                    await values.WriteToAsync(writer);
                }
            }
        }

        private static void WriteQueryResponse(QueryNode query, JObject values, IQueryRegistry registry)
        {
            WriteQueryNodeValue(query, values);
            var childQueries = registry.GetChildren(query.Id);
            foreach (var child in childQueries)
            {
                WriteQueryResponse(child, values, registry);
            }
        }

        private static void WriteQueryNodeValue(QueryNode query, JObject values)
        {
            if (!query.HasAnswer()) return;

            var properties = query.Id.Split(".");

            JToken propVal = values;
            var ind = 0;
            for (; ind < properties.Length - 1; ind++)
            {
                if(propVal[properties[ind]] == null)
                {
                    propVal[properties[ind]] = new JObject();
                }
                propVal = propVal[properties[ind]];
            }
            propVal[properties[ind]] = query.Answer;
        }
    }
}
