using bootstrap.client.Data;
using bootstrap.client.Interfaces;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace bootstrap.client.Collector
{
    public class QueryEnumerator : IQueryEnumerator
    {
        private readonly IQueryRegistry registry;
        private QueryNode current;
        private Queue<QueryNode> currentQ;
        private Stack<Queue<QueryNode>> queries;
        public QueryEnumerator(IQueryRegistry registry)
        {
            this.registry = registry;
        }
        public QueryNode Current => current;

        object IEnumerator.Current => current;

        public void Dispose()
        {
            
        }

        public bool MoveNext()
        {
            if(queries == null)
            {
                Reset();
            }
            if(currentQ == null)
            {
                if (queries.Any()) {
                    currentQ = queries.Pop();
                    current = currentQ.Dequeue();
                }
            }
            else
            {
                if(current.HasAnswer())
                {
                    var childQueriesQ = GetChildQueries(current);
                    if(childQueriesQ.Any())
                    {
                        if (currentQ.Any())
                        {
                            queries.Push(currentQ);
                        }
                        currentQ = childQueriesQ;
                    }
                }
                currentQ = currentQ.Any() ? currentQ : (queries.Any() ? queries.Pop() : null);
                current = currentQ?.Dequeue();
            }
            return current != null;
        }

        private Queue<QueryNode> GetChildQueries(QueryNode current)
        {
            var childQueries = registry.GetChildren(current.Id);
            var q = new Queue<QueryNode>();
            foreach(var child in childQueries)
            {
                var condition = child.HasConditions() ? child.Conditions : null;
                if (condition == null)
                    continue;
                foreach(var pid in condition.Keys)
                {
                    if(!registry.GetQueryNodeById(pid).Answer.Equals(condition[pid]))
                    {
                        //register pending dependents
                        //when supporting queries depending on multiple parents's answers
                        break;
                    }
                    q.Enqueue(child);
                }
            }
            return q;
        }

        public void Reset()
        {
            queries = new Stack<Queue<QueryNode>>();
            var rootQ = new Queue<QueryNode>();
            foreach (var query in registry.GetRootQueries())
            {
                rootQ.Enqueue(query);
            }
            if (rootQ.Any())
            {
                queries.Push(rootQ);
            }
            currentQ = null;
            current = null;
        }
    }
}
