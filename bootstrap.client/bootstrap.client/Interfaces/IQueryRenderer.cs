using bootstrap.client.Data;
using System;
using System.Collections.Generic;
using System.Text;

namespace bootstrap.client.Interfaces
{
    public interface IQueryRenderer
    {
        void Render(QueryNode query);
    }
}
