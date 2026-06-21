[
  { name = "core"
  , version = "1b6e4995e730b5f152106e64d943ae0cc0aa117b"
  , repo = "https://github.com/caffeinelabs/motoko-core"
  , dependencies = [] : List Text
  },
  { name = "ic-logger"
  , version = "f02379ae2dcbbf8c70a88c3e81a6be9dea9e8917"
  , repo = "https://github.com/ninegua/ic-logger"
  , dependencies = [ "core" ]
  },
  { name = "mutable-queue"
  , version = "1be9884297a7b673cb45660c10e3d321b0e94a6a"
  , repo = "https://github.com/ninegua/mutable-queue.mo"
  , dependencies = [ "core" ]
  }
]
