namespace Common.Metrics
{
    public class PrometheusSettings
    {
        public string Route { get; set; }
        public int PortNumber { get; set; }
        public bool UseHttps { get; set; }
    }
}