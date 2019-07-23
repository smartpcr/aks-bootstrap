using bootstrap.client.Data;
using bootstrap.client.Interfaces;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading.Tasks;

namespace bootstrap.client.Readers
{
    public class QueryReader : IQueryReader
    {
        public async Task<IEnumerable<QueryNode>> ReadQueryNodesAsync(string fileName)
        {
            var json = await File.ReadAllTextAsync(fileName);
            JToken queries = await JToken.ReadFromAsync(new JsonTextReader(new StringReader(json)));
            return queries.ToObject<List<QueryNode>>();
        }
    }
}
