"""Download the CC0 Poly Haven assets used by SHADOW PROTOCOL.

All Poly Haven assets are CC0 (https://polyhaven.com/license).
The script records every downloaded asset (id, authors, source URL) in
assets/polyhaven_manifest.json so ASSET_CREDITS.md can be generated from facts.

Usage:  python -I tools/fetch_polyhaven.py <project_root>
"""
import json
import os
import sys
import time
import urllib.request

UA = "ShadowProtocolBuild/1.0 (indie game asset fetch)"
API = "https://api.polyhaven.com"

TEXTURES = {
    # id: use
    "concrete_floor_worn_001": "interior floors",
    "painted_concrete": "interior walls",
    "concrete_wall_008": "exterior walls",
    "asphalt_02": "outdoor ground",
    "metal_plate": "metal floors / platforms",
    "rusty_corrugated_iron": "warehouse cladding",
    "painted_metal_shutter": "doors",
    "worn_tile_floor": "offices / lab floor",
    "rusty_metal_grid": "grates / catwalks",
    "gravel_floor": "perimeter ground",
}
HDRIS = {"kloppenheim_02_puresky": "night sky lighting"}
MODELS = {
    "security_camera_01": "security cameras",
    "metal_office_desk": "offices",
    "steel_frame_shelves_01": "warehouse shelving",
    "wooden_military_crate": "cover crates",
    "old_military_crate": "cover crates",
    "Barrel_01": "barrels",
    "barrel_03": "barrels",
    "concrete_road_barrier": "perimeter cover",
    "power_box_01": "electrical panels",
    "hanging_industrial_lamp": "ceiling lights",
    "mounted_fluorescent_lights": "office lights",
    "propane_tank": "props",
    "metal_jerrycan_green": "props",
    "utility_box_01": "props",
    "exterior_aircon_unit": "props",
    "ammo_box": "ammo pickups",
    "portable_generator": "props",
    "metal_tool_chest": "props",
    "cardboard_box_01": "props",
    "industrial_storage_cart": "props",
    "security_light": "flood lights",
    "classic_laptop": "terminals / intel",
    "vintage_radio_transceiver": "comms room",
    "circuit_board": "lab",
    "modular_industrial_pipes_01": "pipes",
    "metal_trash_can": "props",
    "portable_searchlight": "perimeter",
    "street_lamp_01": "perimeter lights",
    "old_military_compressor": "props",
    "metal_toolbox": "props",
}


def get(url, dest=None, tries=5):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            if dest:
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with open(dest, "wb") as f:
                    f.write(data)
                return dest
            return data
        except Exception as e:  # network on this machine is flaky
            print(f"  retry {i+1} {url}: {e}")
            time.sleep(2 + i * 2)
    raise RuntimeError(f"failed: {url}")


def info(asset_id):
    return json.loads(get(f"{API}/info/{asset_id}"))


def files(asset_id):
    return json.loads(get(f"{API}/files/{asset_id}"))


def main(root):
    out = os.path.join(root, "assets")
    manifest_path = os.path.join(out, "polyhaven_manifest.json")
    manifest = {}
    if os.path.exists(manifest_path):
        manifest = json.load(open(manifest_path, encoding="utf8"))

    for tid, use in TEXTURES.items():
        if tid in manifest:
            continue
        print("texture", tid)
        f = files(tid)
        dest_dir = os.path.join(out, "textures", tid)
        got = []
        for key, fname in (("Diffuse", "albedo"), ("nor_gl", "normal"), ("Rough", "roughness")):
            if key not in f:
                continue
            u = f[key]["1k"]["jpg"]["url"]
            get(u, os.path.join(dest_dir, f"{fname}.jpg"))
            got.append(u)
        i = info(tid)
        manifest[tid] = {"type": "texture", "name": i["name"], "authors": list(i["authors"].keys()),
                         "source": f"https://polyhaven.com/a/{tid}", "files": got, "use": use}
        json.dump(manifest, open(manifest_path, "w", encoding="utf8"), indent=1)

    for hid, use in HDRIS.items():
        if hid in manifest:
            continue
        print("hdri", hid)
        f = files(hid)
        u = f["hdri"]["1k"]["hdr"]["url"]
        get(u, os.path.join(out, "hdri", f"{hid}_1k.hdr"))
        i = info(hid)
        manifest[hid] = {"type": "hdri", "name": i["name"], "authors": list(i["authors"].keys()),
                         "source": f"https://polyhaven.com/a/{hid}", "files": [u], "use": use}
        json.dump(manifest, open(manifest_path, "w", encoding="utf8"), indent=1)

    for mid, use in MODELS.items():
        if mid in manifest:
            continue
        print("model", mid)
        f = files(mid)
        g = f["gltf"]["1k"]["gltf"]
        dest_dir = os.path.join(out, "models", "polyhaven", mid)
        get(g["url"], os.path.join(dest_dir, os.path.basename(g["url"])))
        got = [g["url"]]
        for rel, inc in g.get("include", {}).items():
            get(inc["url"], os.path.join(dest_dir, rel.replace("/", os.sep)))
            got.append(inc["url"])
        i = info(mid)
        manifest[mid] = {"type": "model", "name": i["name"], "authors": list(i["authors"].keys()),
                         "source": f"https://polyhaven.com/a/{mid}", "files": got, "use": use}
        json.dump(manifest, open(manifest_path, "w", encoding="utf8"), indent=1)
    print("done", len(manifest))


if __name__ == "__main__":
    main(sys.argv[1])
