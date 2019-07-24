using System;
using System.Net.NetworkInformation;
using Microsoft.Azure.Documents.SystemFunctions;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Remotion.Linq.Utilities;

namespace Wizard.Assets
{
    public static class JTokenExtension
    {
        public static bool IsPrimitiveValue(this JToken token)
        {
            switch (token.Type)
            {
                case JTokenType.Boolean:
                case JTokenType.Bytes:
                case JTokenType.Comment:
                case JTokenType.Date:
                case JTokenType.Guid:
                case JTokenType.Float:
                case JTokenType.Integer:
                case JTokenType.None:
                case JTokenType.String:
                case JTokenType.Uri:
                case JTokenType.TimeSpan:
                    return true;
                default:
                    return false;
            }
        }

        private static bool IsPrimitiveType(this Type type)
        {
            return type.IsPrimitive || type.IsEnum ||
                   type == typeof(string) || type == typeof(Guid) ||
                   type == typeof(DateTime) || type == typeof(TimeSpan);
        }

        public static object Value(this JToken token, Type type)
        {
            if (type.IsPrimitiveType() && token.IsPrimitiveValue())
            {
                return Convert.ChangeType(token.ToString(), type);
            }

            if (!type.IsPrimitiveType() && !token.IsPrimitiveValue())
            {
                return JsonConvert.DeserializeObject(token.ToString(), type);
            }

            throw new Exception("Incompatible type");
        }
    }
}