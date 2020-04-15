# to be copied into ~/.config/nixpkgs/overlays.nix

let

  nixpkgs-public-local = /etc/nixos/nixpkgs-public/overlay.nix;
  nixpkgs-public = let
    src = builtins.fetchTarball https://gitlab.com/rychly/nixpkgs-public/-/archive/master/nixpkgs-public-master.tar.bz2;
    overlay = src + "/overlay.nix";
  in import (if builtins.pathExists nixpkgs-public-local then nixpkgs-public-local else overlay);

in [
  nixpkgs-public
]
