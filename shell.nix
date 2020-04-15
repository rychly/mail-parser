let

  name = "mail-parser";

  overlays = import ./overlays.nix;

in
  # Running against custom version of nixpkgs or pkgs would be as simple as running `nix-shell --arg nixpkgs /absolute/path/to/nixpkgs`
  # See https://garbas.si/2015/reproducible-development-environments.html
  { nixpkgs ? import <nixpkgs>, pkgs ? nixpkgs { inherit overlays; } }:

pkgs.stdenv.mkDerivation rec {

  inherit name;

  buildInputs = with pkgs; [
    (with luaPackagesCustom; luaPackages.lua.withPackages(ps: with ps; [ luafilesystem luasocket convert-charsets ]))
  ];

  shellHook = ''
    # versions
    echo "# SOFTWARE:" ${builtins.concatStringsSep ", " (map (x: x.name) buildInputs)}
  '';

}
