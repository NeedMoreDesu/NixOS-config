{ home-manager, plasma-manager, ... }:
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit plasma-manager; };
    users.mika.imports = [ ../home ];
  };
}
