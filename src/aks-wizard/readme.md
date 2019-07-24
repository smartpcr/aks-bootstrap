# Goals
based on questions+answers in json file (passed in as argument), the solution will generate
- azure resources
    - env.yaml file
    - values.yaml file
- service manifest file
    - sln
    - csproj
    - nuget pkgs
    - common libs
    - update DI and use extension method to hookup
        - kv client
        - cosmos db client
        - ssl cert (always the same within aks cluster)
        - auth
