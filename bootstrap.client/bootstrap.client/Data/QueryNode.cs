using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace bootstrap.client.Data
{
    public class QueryNode
    {
        public string Id { get; private set; }
        public string DisplayText { get; private set; }
        public IEnumerable<string> ParentIds { get; private set; }
        public IEnumerable<string> Options { get; private set; }
        public IDictionary<string, string> Conditions { get; private set; }
        public bool IgnoreSave { get; set; }

        public ResponseType ResponseType { get; set; }

        public bool HasParents()
        {
            return ParentIds != null && ParentIds.Any();
        }

        public bool HasConditions()
        {
            return Conditions != null && Conditions.Any();
        }

        public bool HasOptions()
        {
            return Options != null && Options.Any();
        }

        public string Answer { get; set; }

        public QueryNode(string id, string text)
        {
            Id = id;
            DisplayText = text;
            ParentIds = new List<string>();
            Options = new List<string>();
            Conditions = new Dictionary<string, string>();
        }

        internal bool HasAnswer()
        {
            return string.IsNullOrEmpty(Answer) == false;
        }
    }
}
