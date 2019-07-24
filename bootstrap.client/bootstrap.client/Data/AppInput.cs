using System;
using System.Collections.Generic;
using System.Text;

namespace bootstrap.client.Data
{
    public class AppInput
    {
        public string InputFileName { get; private set; }
        public string OutFileName { get; private set; }

        public AppInput(string inFile, string outFile)
        {
            InputFileName = inFile;
            OutFileName = outFile;
        }
    }
}
