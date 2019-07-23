using System.Collections.Generic;
using System.Threading.Tasks;
using bootstrap.client.Data;

namespace bootstrap.client.Interfaces
{
    public interface IQueryReader
    {
        Task<IEnumerable<QueryNode>> ReadQueryNodesAsync(string fileName);
    }
}