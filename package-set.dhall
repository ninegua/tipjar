let upstream = https://github.com/dfinity/vessel-package-set/releases/download/mo-0.6.18-20220107/package-set.dhall sha256:af8b8dbe762468ce9b002fb0c62e65e1a3ee0d003e793c4404a16f8531a71b59
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
