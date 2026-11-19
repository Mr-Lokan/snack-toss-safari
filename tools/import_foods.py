"""Package toon_foods.glb after Studio Import 3D and Save to File (.rbxmx)."""
import argparse
import re
import xml.etree.ElementTree as ET
from pathlib import Path

import build


def property_node(item, name):
    return item.find(f"Properties/*[@name='{name}']")


def name_of(item):
    node = property_node(item, "Name")
    return node.text if node is not None else ""


def set_property(item, tag, name, value):
    node = property_node(item, name)
    if node is None:
        node = ET.SubElement(item.find("Properties"), tag, name=name)
    node.text = value


def has_asset(item, names):
    for name in names:
        node = property_node(item, name)
        if node is not None and re.search(r"rbxassetid://\d+|https://[^ ]+[?&]id=\d+",
                                          "".join(node.itertext())):
            return True
    return False


def package(source):
    xml = ET.parse(source).getroot()
    groups = {}
    for item in xml.iter("Item"):
        match = re.fullmatch(r"(\w+)_(Body|Outline)", name_of(item))
        if item.get("class") == "MeshPart" and match:
            name, role = match.groups()
            parts = groups.setdefault(name, {})
            if role in parts:
                raise ValueError(f"Duplicate mesh: {name}_{role}")
            parts[role] = item
    names = {"Carrot", "Apple", "Banana", "Toast", "Cheese", "Steak", "Watermelon",
             "Cake", "Sushi", "GoldenApple", "RainbowCandy"}
    if set(groups) != names or any(set(parts) != {"Body", "Outline"} for parts in groups.values()):
        raise ValueError("Expected exactly 11 food models with both Body and Outline.")

    result = ET.Element("roblox", version="4")
    folder = ET.SubElement(result, "Item", {"class": "Folder", "referent": "ToonFoodsRoot"})
    ET.SubElement(folder, "Properties")
    set_property(folder, "string", "Name", "ToonFoods")
    for index, (name, parts) in enumerate(sorted(groups.items())):
        model = ET.SubElement(folder, "Item", {"class": "Model", "referent": f"ToonFood{index}"})
        ET.SubElement(model, "Properties")
        set_property(model, "string", "Name", name)
        for role, part in parts.items():
            if not has_asset(part, ("MeshId", "MeshContent")):
                raise ValueError(f"{name}_{role} has no uploaded mesh ID.")
            if role == "Body" and not has_asset(part, ("TextureID", "TextureContent")):
                surfaces = part.findall("Item[@class='SurfaceAppearance']")
                if not any(has_asset(surface, ("ColorMap", "ColorMapContent")) for surface in surfaces):
                    raise ValueError(f"{name}_{role} has no uploaded color texture.")
            set_property(part, "string", "Name", role)
            for prop in ("CanCollide", "CanTouch", "CanQuery", "DoubleSided"):
                set_property(part, "bool", prop, "false")
            set_property(part, "bool", "Anchored", "true")
            if role == "Outline":
                set_property(part, "bool", "CastShadow", "false")
                set_property(part, "Color3uint8", "Color3uint8", str(0xFF1A1416))
            model.append(part)
    shared = xml.find("SharedStrings")
    if shared is not None:
        result.append(shared)
    return ET.ElementTree(result)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="The imported food scene saved as .rbxmx in Studio")
    args = parser.parse_args()
    destination = Path(build.SRC) / "ReplicatedStorage" / "ToonFoods.rbxmx"
    package(args.source).write(destination, encoding="utf-8", xml_declaration=True)
    build.main()
