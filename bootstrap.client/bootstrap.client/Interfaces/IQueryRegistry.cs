using bootstrap.client.Data;
using System.Collections.Generic;

namespace bootstrap.client.Interfaces
{
    public interface IQueryRegistry
    {
        IEnumerable<QueryNode> GetChildren(string parentId);
        QueryNode GetQueryNodeById(string nodeId);
        IEnumerable<QueryNode> GetRootQueries();
        void RegisterNode(QueryNode node);
    }
}