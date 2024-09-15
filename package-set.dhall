let upstream = https://github.com/dfinity/vessel-package-set/releases/download/mo-0.12.1-20240808/package-set.dhall sha256:975d4b33f3ce1fa051c73e45fab69dd187dba6b037b6d2e5568ccac26c477d4f
let Package =
    { name : Text, version : Text, repo : Text, dependencies : List Text }

let
  -- This is where you can add your own packages to the package-set
  additions =
    [
      { name = "accountid"
      , repo = "https://github.com/stephenandrews/motoko-accountid"
      , version = "06726b1625fea8870bc8c248d661b11a4ebfe7ae"
      , dependencies = [ "base" ]
      },
      { name = "ic-logger"
      , repo = "https://github.com/ninegua/ic-logger"
      , version = "95e06542158fc750be828081b57834062aa83357"
      , dependencies = [ "base" ]
      },
      { name = "mutable-queue"
      , repo = "https://github.com/ninegua/mutable-queue.mo"
      , version = "2759a3b8d61acba560cb3791bc0ee730a6ea8485"
      , dependencies = [ "base" ]
      }
    ] : List Package

let
  {- This is where you can override existing packages in the package-set

     For example, if you wanted to use version `v2.0.0` of the foo library:
     let overrides = [
         { name = "foo"
         , version = "v2.0.0"
         , repo = "https://github.com/bar/foo"
         , dependencies = [] : List Text
         }
     ]
  -}
  overrides =
    [] : List Package

in  upstream # additions # overrides
