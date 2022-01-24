{ pkgs ? import <nixpkgs> {} }:
let
  ic-utils = import (builtins.fetchGit {
    url = "https://github.com/ninegua/ic-utils";
    rev = "6e9b645e667fb59f51ad8cfa40e2fd7fdd7e52d0";
    ref = "refs/heads/main";
  }) { inherit pkgs; };
in pkgs.mkShell { nativeBuildInputs = [ ic-utils pkgs.wasmtime pkgs.pandoc pkgs.nodejs pkgs.nodePackages.prettier ]; }
