{ lockPath }:
let
  lock = builtins.fromJSON (builtins.readFile lockPath);
  roots = lock.nodes.root.inputs;

  refFor = locked:
    if locked.type == "github" then
      "github:${locked.owner}/${locked.repo}/${locked.rev}"
    else if locked.type == "git" then
      "git+${locked.url}?rev=${locked.rev}"
      + (if locked.submodules or false then "&submodules=1" else "")
    else
      throw "unsupported locked input type: ${locked.type}";

  row = name:
    let
      locked = (lock.nodes.${roots.${name}} or { }).locked or { };
    in
    "${name}\t${locked.rev or "?"}\t${toString (locked.lastModified or 0)}\t${refFor locked}";
in
map row (builtins.attrNames roots)
