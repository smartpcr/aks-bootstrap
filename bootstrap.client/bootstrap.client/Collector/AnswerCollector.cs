using bootstrap.client.Data;
using bootstrap.client.Interfaces;
using System;
using System.Collections.Generic;
using System.Text;

namespace bootstrap.client.Collector
{
    public class AnswerCollector : IAnswerCollector
    {
        private readonly IQueryEnumerator enumerator;
        private readonly IQueryRenderer renderer;

        public AnswerCollector(IQueryEnumerator enumerator, IQueryRenderer renderer)
        {
            this.enumerator = enumerator;
            this.renderer = renderer;
        }

        public void Collect()
        {
            while (enumerator.MoveNext())
            {
                renderer.Render(enumerator.Current);
            }
        }
    }
}
