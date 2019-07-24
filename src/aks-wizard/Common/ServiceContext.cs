namespace Common
{
    public class ServiceContext
    {
        public string Role { get; set; }
        public string Namespace { get; set; }
        public string Version { get; set; }
        public string[] Tags { get; set; }
        public OrchestratorType Orchestrator { get; set; }
        public string Description { get; set; }
    }

    public enum OrchestratorType
    {
        K8S,     // running inside kubernetes cluster
        SF,      // running inside service fabric cluster
        None    // running docker image on local
    }
}