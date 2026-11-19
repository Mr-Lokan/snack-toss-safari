"""Builds SnackTossSafari.rbxlx from src/.

python -I tools/build.py

src/<Service>/...          -> service in the place
  folder                   -> Folder
  Name.server.lua          -> Script
  Name.client.lua          -> LocalScript
  Name.lua                 -> ModuleScript
  Name.rbxmx               -> instances saved from Studio (Save to File, XML), embedded as is
"""
import os
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
OUTPUT = os.path.join(ROOT, "SnackTossSafari.rbxlx")

# папки, которые в плейсе являются не Folder, а своим классом
SPECIAL = {
    "StarterPlayer/StarterPlayerScripts": "StarterPlayerScripts",
    "StarterPlayer/StarterCharacterScripts": "StarterCharacterScripts",
}

# свойства сервисов, которые нельзя поменять из скрипта
SERVICE_PROPS = {
    # карта длинная, со стримингом клиент не видит землю там, куда летит еда
    "Workspace": '<bool name="StreamingEnabled">false</bool>',
    # на базе 5 вольеров: в одном сервере до 5 игроков
    "Players": '<int name="MaxPlayersInternal">5</int><int name="PreferredPlayersInternal">5</int>',
}


class Writer:
    def __init__(self):
        self.ref = 0
        self.lines = []
        self.shared = {}  # md5 -> <SharedString> из встроенных моделей

    def open(self, class_name, name, extra=""):
        self.ref += 1
        self.lines.append(f'<Item class="{class_name}" referent="RBX{self.ref:08X}">')
        self.lines.append(f'<Properties><string name="Name">{escape(name)}</string>{extra}</Properties>')

    def close(self):
        self.lines.append("</Item>")

    def script(self, class_name, name, path):
        with open(path, "r", encoding="utf-8-sig") as f:
            source = f.read().replace("\r\n", "\n")
        cdata = "<![CDATA[" + source.replace("]]>", "]]]]><![CDATA[>") + "]]>"
        self.open(class_name, name, f'<ProtectedString name="Source">{cdata}</ProtectedString>')
        self.close()

    def model(self, path):
        """Модель из Studio (.rbxmx): меши, загруженные через Import 3D, со всеми их свойствами.
        Ссылки внутри файла (PrimaryPart) переименовываются, чтобы не пересечься с остальным плейсом."""
        root = ET.parse(path).getroot()
        remap = {}
        for item in root.iter("Item"):
            self.ref += 1
            new = f"RBX{self.ref:08X}"
            remap[item.get("referent")] = new
            item.set("referent", new)
        for ref in root.iter("Ref"):
            if ref.text in remap:
                ref.text = remap[ref.text]
        for item in root.findall("Item"):
            self.lines.append(ET.tostring(item, encoding="unicode"))
        shared = root.find("SharedStrings")
        if shared is not None:
            for s in shared:
                self.shared.setdefault(s.get("md5"), ET.tostring(s, encoding="unicode"))
        return len(remap)


def script_kind(filename):
    if filename.endswith(".server.lua"):
        return "Script", filename[: -len(".server.lua")]
    if filename.endswith(".client.lua"):
        return "LocalScript", filename[: -len(".client.lua")]
    if filename.endswith(".lua"):
        return "ModuleScript", filename[: -len(".lua")]
    return None, None


def walk(w, path, rel):
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)
        child_rel = f"{rel}/{entry}"
        if os.path.isdir(full):
            w.open(SPECIAL.get(child_rel, "Folder"), entry)
            walk(w, full, child_rel)
            w.close()
        elif entry.endswith(".rbxmx"):
            count = w.model(full)
            print(f"  {'Model':12} {child_rel} ({count} instances)")
        else:
            class_name, name = script_kind(entry)
            if class_name:
                w.script(class_name, name, full)
                print(f"  {class_name:12} {child_rel}")


def main():
    w = Writer()
    for service in sorted(os.listdir(SRC)):
        path = os.path.join(SRC, service)
        if os.path.isdir(path):
            w.open(service, service, SERVICE_PROPS.get(service, ""))
            walk(w, path, service)
            w.close()
    for service, extra in SERVICE_PROPS.items():
        if not os.path.isdir(os.path.join(SRC, service)):
            w.open(service, service, extra)
            w.close()

    header = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
              'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
              'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">')
    shared = ""
    if w.shared:
        shared = "<SharedStrings>" + "".join(w.shared.values()) + "</SharedStrings>\n"
    with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(header + "\n" + "\n".join(w.lines) + "\n" + shared + "</roblox>\n")
    print(f"saved {OUTPUT} ({w.ref} instances)")


if __name__ == "__main__":
    sys.exit(main())
