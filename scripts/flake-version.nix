{ flakeRef, name, system ? builtins.currentSystem }:
let
  flake = builtins.getFlake flakeRef;
  tryString = x:
    let
      r = builtins.tryEval x;
    in
    if r.success && builtins.isString r.value && r.value != "" then r.value else null;
  top = tryString (flake.version or null);
  lib = tryString (flake.lib.version or null);
  defaultPkg = tryString (flake.packages.${system}.default.version or null);
  namedPkg = tryString (flake.packages.${system}.${name}.version or null);
  candidates =
    if name == "nixpkgs" then [ lib top ] else [ top defaultPkg namedPkg ];
  values = builtins.filter (x: x != null) candidates;
in
if values == [ ] then "" else builtins.head values
