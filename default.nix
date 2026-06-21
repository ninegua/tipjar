# The default hash is with nixpkgs unstable. Supply `pnpmDepsHash` if you want to pin nixpkgs.
{ pkgs ? import <nixpkgs> { }
, ic-version ? "a17247bd86c7aa4e87742bf74d108614580f216d" }:
with pkgs;
let
  ic-nix = fetchFromGitHub {
    owner = "ninegua";
    repo = "ic-nix";
    rev = "20260616";
    sha256 = "sha256-C/er0a+IFaUuq+nffzgmXhy7YFAxl35lDkV2WNZ8Iis=";
  };
  ic-pkgs = import "${ic-nix}/default.nix" { inherit pkgs; };
  moc = ic-pkgs.motoko.moc;
  didc = ic-pkgs.utils.candid;
  vessel = ic-pkgs.utils.vessel;

  dhall-to-nix = file:
    import (stdenv.mkDerivation {
      name = "${builtins.baseNameOf file}.nix";
      buildCommand = ''
        export XDG_CACHE_HOME="$TMPDIR/dhall-cache";
        dhall-to-nix <<< "${file}" > $out
      '';
      buildInputs = [ dhall-nix ];
    });

  blackhole-did = builtins.fetchurl
    "https://github.com/ninegua/ic-blackhole/releases/download/0.0.0/blackhole.did";
  cycles-ledger-did = builtins.fetchurl
    "https://github.com/dfinity/cycles-ledger/releases/download/cycles-ledger-v1.0.6/cycles-ledger.did";
  icp-ledger-did = builtins.fetchurl
    "https://raw.githubusercontent.com/dfinity/ic/${ic-version}/rs/rosetta-api/icp_ledger/ledger.did";
  cmc-did = builtins.fetchurl
    "https://raw.githubusercontent.com/dfinity/ic/${ic-version}/rs/nns/cmc/cmc.did";

  moc-flags = builtins.concatStringsSep " " (builtins.builtins.map (pkg:
    "--package ${pkg.name} ${
      builtins.fetchGit {
        url = pkg.repo;
        rev = pkg.version;
      }
    }/src") (dhall-to-nix ./package-set.dhall));

  backend = stdenv.mkDerivation {
    version = "0.1.0";
    pname = "tipjar-backend";
    buildInputs = [ moc vessel ];
    src = lib.cleanSourceWith (rec {
      src = ./.;
      filter = path: type:
        let relPath = lib.removePrefix (toString src + "/") (toString path);
        in lib.any (prefix: lib.hasPrefix prefix relPath) [
          "Makefile"
          "src"
        ];
    });
    configurePhase = "mkdir .vessel";
    buildPhase =
      "make backend DIDC=${didc}/bin/didc MOC_FLAGS='${moc-flags}' CMC_DID=${cmc-did} BLACKHOLE_DID=${blackhole-did} CYCLES_LEDGER_DID=${cycles-ledger-did} ICP_LEDGER_DID=${icp-ledger-did}";
    installPhase = "mkdir -p $out && cp -r dist/{logger,tipjar}.{did,wasm} $out/";
  };

in { inherit backend; }
