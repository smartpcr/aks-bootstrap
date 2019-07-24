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
            PrintLn(query.DisplayText);
            if(!query.HasOptions())
            {
                var answer = Console.ReadLine().Trim();
                while(!IsValid(answer))
                {
                    PrintLn("Invalid response, please try again ..");
                    answer = ReadResponse();
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
                RenderOptions(options);
                var answer = ReadResponse().ToLower();
                while (!IsValid(answer, options))
                {
                    PrintLn("Invalid response, please try again ..");
                    answer = ReadResponse();
                }
                query.Answer = options[answer];
            }
        }

        private void RenderOptions(Dictionary<string, string> options)
        {
            foreach(var opt in options.Keys)
            {
                PrintLn($"{opt}. {options[opt]}");
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

        private void PrintLn(string message)
        {
            Console.WriteLine(message);
        }
        private void Print(string message)
        {
            Console.Write(message);
        }

        private string ReadResponse()
        {
            Print("=> ");
            return Console.ReadLine().Trim();
        }
    }
}
