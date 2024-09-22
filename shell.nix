let
  pkgs = import <nixpkgs> {};
in pkgs.mkShell {
  buildInputs = [
    pkgs.gleam
    pkgs.erlang_27
    pkgs.rebar3
  ];
}

