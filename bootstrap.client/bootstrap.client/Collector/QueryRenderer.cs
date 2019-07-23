using bootstrap.client.Data;
using bootstrap.client.Interfaces;
using System;
using System.Collections.Generic;
using System.Text;

namespace bootstrap.client.Collector
{
    public class QueryRenderer : IQueryRenderer
    {
        public void Render(QueryNode query)
        {
            Console.WriteLine(query.DisplayText);
            if(!query.HasOptions())
            {
                var answer = Console.ReadLine().Trim();
                while(!IsValid(answer))
                {
                    Console.WriteLine("Invalid response, please try again ..");
                    answer = Console.ReadLine().Trim();
                }
                query.Answer = answer;
            }
            else
            {
                var options = new Dictionary<string, string>();
                char ind = 'a';
                foreach(var opt in query.Options)
                {
                    options.Add(ind.ToString(), opt);
                    ind++;
                }
                var answer = Console.ReadLine().Trim().ToLower();
                while (!IsValid(answer, options))
                {
                    Console.WriteLine("Invalid response, please try again ..");
                    answer = Console.ReadLine().Trim();
                }
                query.Answer = options[answer];
            }
        }

        private bool IsValid(string answer, Dictionary<string, string> options)
        {
            return !string.IsNullOrEmpty(answer) && options.ContainsKey(answer);
        }

        private bool IsValid(string answer)
        {
            return !string.IsNullOrEmpty(answer);
        }
    }
}
