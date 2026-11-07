"""Builds .rbxmx packages from .luau sources so they can be imported into Studio in one go."""

from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build"
OUT.mkdir(exist_ok=True)

counter = 0


def ref() -> str:
    global counter
    value = f"RBX{counter}"
    counter += 1
    return value


def item(cls: str, children: str, name: str | None = None) -> str:
    props = []
    if name:
        props.append(f'      <string name="Name">{escape(name)}</string>')
    if cls in {"Script", "LocalScript", "ModuleScript"}:
        pass
    body = ""
    if props:
        body += "    <Properties>\n" + "\n".join(props) + "\n    </Properties>\n"
    return f'  <Item class="{cls}" referent="{ref()}">\n{body}{children}  </Item>\n'


def script_item(cls: str, name: str, source: str) -> str:
    children = (
        "    <Properties>\n"
        f'      <string name="Name">{escape(name)}</string>\n'
        f'      <ProtectedString name="Source"><![CDATA[{source}]]></ProtectedString>\n'
        "    </Properties>\n"
    )
    return f'  <Item class="{cls}" referent="{ref()}">\n{children}  </Item>\n'


def folder(name: str, scripts: list[tuple[str, str, str]]) -> str:
    inner = "".join(script_item(cls, sname, source) for cls, sname, source in scripts)
    return (
        f'  <Item class="Folder" referent="{ref()}">\n'
        "    <Properties>\n"
        f'      <string name="Name">{escape(name)}</string>\n'
        "    </Properties>\n"
        f"{inner}"
        "  </Item>\n"
    )


def wrap(items: str) -> str:
    return (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
        f"{items}</roblox>\n"
    )


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def module(name: str, path: Path) -> tuple[str, str, str]:
    return ("ModuleScript", name, read(path))


def build_replicated() -> None:
    modules = [module(p.stem, p) for p in sorted((ROOT / "Shared").glob("*.luau"))]
    (OUT / "replicated_storage.rbxmx").write_text(wrap(folder("Combat", modules)), encoding="utf-8")


def build_server() -> None:
    bootstrap = read(ROOT / "Server" / "CombatBootstrap.server.luau")
    modules = [module(p.stem, p) for p in sorted((ROOT / "Server" / "Combat").glob("*.luau"))]
    items = script_item("Script", "CombatBootstrap", bootstrap) + folder("Combat", modules)
    (OUT / "server_script_service.rbxmx").write_text(wrap(items), encoding="utf-8")


def build_client() -> None:
    bootstrap = read(ROOT / "Client" / "CombatClient.client.luau")
    modules = [module(p.stem, p) for p in sorted((ROOT / "Client" / "Combat").glob("*.luau"))]
    items = script_item("LocalScript", "CombatClient", bootstrap) + folder("Combat", modules)
    (OUT / "starter_player_scripts.rbxmx").write_text(wrap(items), encoding="utf-8")


if __name__ == "__main__":
    build_replicated()
    build_server()
    build_client()
    for file in sorted(OUT.glob("*.rbxmx")):
        print(f"{file.name}: {file.stat().st_size} bytes")
