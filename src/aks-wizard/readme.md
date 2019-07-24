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

# Usage

## collect answers to questions and generate evidence

TODO:

## generate infra setup scripts
``` cmd
aksbootstrap infra gen "<evidence file>" "<script output folder>"
```

## run infra setup
``` cmd
aksbootstrap infra run "<script folder>"
```

## generate solution
``` cmd
aksbootstrap app gen "<evidence file>" "<code output folder>"
```

## deploy solution to aks
``` cmd
aksbootstrap app deploy "<service manifest file>" "<script folder>"
```

## run solution on local
``` cmd
aksbootstrap app run "<service manifest file>" "<script folder>"
```