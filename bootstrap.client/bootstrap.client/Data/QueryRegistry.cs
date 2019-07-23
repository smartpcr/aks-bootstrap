using bootstrap.client.Interfaces;
using System;
using System.Collections.Generic;
using System.Linq;

namespace bootstrap.client.Data
{
    public class QueryRegistry : IQueryRegistry
    {
        private IDictionary<string, List<QueryNode>> Children { get; set; }
        private IDictionary<string, QueryNode> NodeMap { get; set; }
        private List<QueryNode> Roots { get; set; }

        public QueryRegistry()
        {
            Children = new Dictionary<string, List<QueryNode>>();
            NodeMap = new Dictionary<string, QueryNode>();
            Roots = new List<QueryNode>();
        }

        public void RegisterNode(QueryNode node)
        {
            if (NodeMap.ContainsKey(node.Id))
            {
                return;
            }
            NodeMap.Add(node.Id, node);
            if (!node.HasParents())
            {
                Roots.Add(node);
                return;
            }
            foreach (var pid in node.ParentIds)
            {
                var childrenList = Children.ContainsKey(pid) ? Children[pid] : new List<QueryNode>();
                childrenList.Add(node);
                Children[pid] = childrenList;
            }
        }

        public IEnumerable<QueryNode> GetRootQueries()
        {
            return Roots.ToArray<QueryNode>();
        }

        public QueryNode GetQueryNodeById(string nodeId)
        {
            return NodeMap[nodeId];
        }

        public IEnumerable<QueryNode> GetChildren(string parentId)
        {
            return Children[parentId].ToArray<QueryNode>();
        }
    }
}
