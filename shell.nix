{ pkgs ? import <nixpkgs> { } }:
let
  dfx-env = import (fetchTarball
    "https://github.com/ninegua/ic-nix/releases/download/20260616/dfx-env.tar.gz")
    { };
in dfx-env.overrideAttrs (old: {
  # disable icp-cli telemetry
  DO_NOT_TRACK = 1;
  nativeBuildInputs = old.nativeBuildInputs
    ++ (with pkgs; [ wasmtime pandoc nodejs prettier ]);
})
