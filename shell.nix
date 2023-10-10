{ pkgs ? import <nixpkgs> { } }:
let
  dfx-env = import (fetchTarball
    "https://github.com/ninegua/ic-nix/releases/download/20231003/dfx-env.tar.gz")
    { };
in dfx-env.overrideAttrs (old: {
  nativeBuildInputs = old.nativeBuildInputs ++ [
    pkgs.wasmtime
    pkgs.pandoc
    pkgs.nodejs
    pkgs.nodePackages.prettier
  ];
})
