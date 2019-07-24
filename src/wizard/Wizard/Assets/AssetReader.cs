using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace Wizard.Assets
{
    public class AssetReader
    {
        private static IEnumerable _components;
        private static Dictionary<Type, ObjectPathAttribute> _assetsWithObjPath;
        private static Dictionary<Type, IList<(PropertyInfo prop, PropertyPathAttribute propPath)>> _assetsWithPropPaths;

        public static IEnumerable Components
        {
            get
            {
                if (_components == null)
                {
                    _components = typeof(AssetReader).Assembly.GetTypes()
                        .Where(t => typeof(IAsset).IsAssignableFrom(t) && !t.IsAbstract && t.IsClass)
                        .Select(t => Activator.CreateInstance(t) as IAsset);
                }

                return _components;
            }
        }

        public static Dictionary<Type, ObjectPathAttribute> AssetsWithObjPath
        {
            get
            {
                if (_assetsWithObjPath == null)
                {
                    _assetsWithObjPath = typeof(AssetReader).Assembly.GetTypes()
                        .Where(t =>
                            typeof(IAsset).IsAssignableFrom(t) &&
                            !t.IsAbstract &&
                            t.IsClass &&
                            t.GetCustomAttribute<ObjectPathAttribute>() != null)
                        .ToDictionary(t => t, t => t.GetCustomAttribute<ObjectPathAttribute>());
                }

                return _assetsWithObjPath;
            }
        }

        public static Dictionary<Type, IList<(PropertyInfo prop, PropertyPathAttribute propPath)>> AssetsWithPropPaths
        {
            get
            {
                if (_assetsWithPropPaths == null)
                {
                    _assetsWithPropPaths = new Dictionary<Type, IList<(PropertyInfo prop, PropertyPathAttribute propPath)>>();
                    foreach (var component in Components)
                    {
                        var props = component.GetType().GetProperties()
                            .Where(p => p.GetCustomAttribute<PropertyPathAttribute>() != null)
                            .Select(p => (p, p.GetCustomAttribute<PropertyPathAttribute>()))
                            .ToList();
                        _assetsWithPropPaths.Add(component.GetType(), props);
                    }
                }

                return _assetsWithPropPaths;
            }
        }

        public static IEnumerable<IAsset> Read(string manifestJsonFile)
        {
            var jtoken = JToken.Parse(File.ReadAllText(manifestJsonFile));
            List<IAsset> instances = new List<IAsset>();

            foreach (var component in Components)
            {
                if (AssetsWithObjPath.ContainsKey(component.GetType()))
                {
                    var objPath = AssetsWithObjPath[component.GetType()];
                    if (objPath.AllowMultiple)
                    {
                        List<IAsset> array = new List<IAsset>();
                        var componentInstance = Activator.CreateInstance(component.GetType()) as IAssetArray;
                        if (componentInstance == null)
                        {
                            throw new Exception("Array must implements 'IAssetArray'");
                        }

                        var itemsProp = componentInstance.GetType().GetProperty("Items");
                        var itemType = componentInstance.ItemType;

                        var tokens = jtoken.SelectTokens(objPath.JPath).ToList();
                        if (tokens.Count == 1)
                        {
                            if (tokens[0] is JArray tokenArray)
                            {
                                foreach (var token in tokenArray)
                                {
                                    if (token.Value(itemType) is IAsset instance)
                                    {
                                        array.Add(instance);
                                    }
                                }
                            }
                        }
                        else
                        {
                            foreach (var token in tokens)
                            {
                                if (token.Value(itemType) is IAsset instance)
                                {
                                    array.Add(instance);
                                }
                            }
                        }


                        itemsProp.SetValue(componentInstance, array.ToArray());
                        instances.Add(componentInstance as IAsset);
                    }
                    else
                    {
                        var token = jtoken.SelectToken(objPath.JPath);
                        if (token != null)
                        {
                            if (token.Value(component.GetType()) is IAsset instance)
                            {
                                instances.Add(instance);
                            }
                        }
                    }
                }
                else if (AssetsWithPropPaths.ContainsKey(component.GetType()))
                {
                    var propPaths = AssetsWithPropPaths[component.GetType()];
                    var instance = Activator.CreateInstance(component.GetType()) as IAsset;
                    foreach (var tuple in propPaths)
                    {
                        if (tuple.propPath.IsArray)
                        {
                            var itemType = tuple.prop.PropertyType.GetElementType();
                            var tokens = jtoken.SelectTokens(tuple.propPath.JPath);
                            if (tokens?.Any() == true)
                            {
                                ArrayList array = new ArrayList();
                                foreach (var token in tokens)
                                {
                                    var propValue = token.Value(itemType);
                                    if (propValue != null)
                                    {
                                        array.Add(propValue);
                                    }
                                }
                                tuple.prop.SetValue(instance, array.ToArray());
                            }
                        }
                        else
                        {
                            var token = jtoken.SelectToken(tuple.propPath.JPath);
                            var propValue = token?.Value(tuple.prop.PropertyType);
                            if (propValue != null)
                            {
                                tuple.prop.SetValue(instance, propValue);
                            }
                        }
                    }

                    instances.Add(instance);
                }
            }

            return instances.OrderBy(c => c.SortOrder);
        }
    }
}