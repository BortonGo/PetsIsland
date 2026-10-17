#!/usr/bin/env python3
"""Check release metadata and packaging. Does not claim App Store approval."""
import argparse
import json
import plistlib
import re
import subprocess
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
EMAIL = "bortone52@yandex.ru"
PRODUCTS = {f"org.bortongo.PetIsland.tip.{size}" for size in ("small", "medium", "large")}


def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def plist(path):
    with path.open("rb") as stream:
        return plistlib.load(stream)


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        for attribute in ("href", "src"):
            if attribute in attrs:
                self.links.append(attrs[attribute])
        require(tag != "script", "Support pages must remain script-free")


def check_sources():
    manifest = plist(ROOT / "SharedResources/PrivacyInfo.xcprivacy")
    require(manifest["NSPrivacyTracking"] is False, "Unexpected tracking declaration")
    require(manifest["NSPrivacyCollectedDataTypes"] == [], "Review changed data collection")
    require(manifest["NSPrivacyAccessedAPITypes"] == [{
        "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
        "NSPrivacyAccessedAPITypeReasons": ["1C8F.1"],
    }], "Review required-reason API declarations")
    require(plist(ROOT / "PetIsland/Info.plist")["ITSAppUsesNonExemptEncryption"] is False,
            "Missing encryption declaration")
    for target in ("PetIsland", "PetIslandLiveActivity"):
        require(set(plist(ROOT / target / "Info.plist").get("CFBundleLocalizations", [])) == {"en", "ru"},
                f"{target}: missing supported app languages")
        require(plist(ROOT / target / f"{target}.entitlements")["com.apple.security.application-groups"]
                == ["group.org.bortongo.PetIsland"], f"{target}: App Group mismatch")

    project = json.loads(subprocess.check_output([
        "plutil", "-convert", "json", "-o", "-", str(ROOT / "PetIsland.xcodeproj/project.pbxproj")]))
    objects = project["objects"]
    for target in (item for item in objects.values() if item.get("isa") == "PBXNativeTarget"):
        resources = []
        for phase_id in target["buildPhases"]:
            phase = objects[phase_id]
            if phase["isa"] == "PBXResourcesBuildPhase":
                resources += [objects[objects[file_id]["fileRef"]]["path"] for file_id in phase["files"]]
        if target["name"] in ("PetIsland", "PetIslandLiveActivity"):
            require("PrivacyInfo.xcprivacy" in resources, f"{target['name']}: manifest not bundled")
            require(not any(path.endswith(".storekit") for path in resources), "Test prices in shipping target")

    config = json.loads((ROOT / "Configuration/PetIslandTips.storekit").read_text())
    require({p["productID"] for p in config["products"]} == PRODUCTS, "Tip product IDs differ")
    for product in config["products"]:
        require(product["type"] == "Consumable", "Tips must be repeatable, non-subscription purchases")
        require({x["locale"] for x in product["localizations"]} == {"en_US", "ru"}, "Missing tip translation")
    strings = json.loads((ROOT / "PetIsland/Resources/ReleaseSupport.xcstrings").read_text())
    for key, item in strings["strings"].items():
        for language in ("en", "ru"):
            unit = item.get("localizations", {}).get(language, {}).get("stringUnit", {})
            require(unit.get("state") == "translated" and unit.get("value"), f"Untranslated {language}: {key}")
    sources = "\n".join((ROOT / "PetIsland/Features" / name).read_text() for name in (
        "AuthorSupportView.swift", "SupportPrivacyView.swift", "AppLanguageView.swift", "Sheets.swift"))
    direct = re.findall(r'String\(localized: "([^"\\]*(?:\\.[^"\\]*)*)", table: "ReleaseSupport"\)', sources)
    for key in direct:
        require(key in strings["strings"], f"Missing localized key: {key}")

    for catalog in (ROOT / "PetIsland/Resources").glob("*.xcstrings"):
        data = json.loads(catalog.read_text())
        require(data["sourceLanguage"] == "en", f"Unexpected source language in {catalog.name}")
        for key, item in data["strings"].items():
            if not key or item.get("shouldTranslate") is False:
                continue
            translation = item.get("localizations", {}).get("ru", {})
            units = re.findall(r'"state"\s*:\s*"([^"]+)"', json.dumps(translation))
            require(units and all(state == "translated" for state in units),
                    f"Missing Russian translation in {catalog.name}: {key}")

    icons = list((ROOT / "PetIsland/Assets.xcassets").glob("*.appiconset/Contents.json"))
    require(icons, "No app icons")
    for catalog in icons:
        for item in json.loads(catalog.read_text())["images"]:
            if not item.get("filename"):
                continue
            path = catalog.parent / item["filename"]
            with Image.open(path) as image:
                require(image.mode not in ("RGBA", "LA") and "transparency" not in image.info,
                        f"App icon has an alpha channel: {path.name}")
                expected = tuple(round(float(x) * float(item.get("scale", "1x")[:-1]))
                                 for x in item["size"].split("x"))
                require(image.size == expected, f"Wrong app icon dimensions: {path.name}")

    site = ROOT / "Docs/AppStoreSite"
    pages = {}
    for page in site.glob("*.html"):
        text = page.read_text()
        require(EMAIL in text and 'name="viewport"' in text, f"Incomplete support page: {page.name}")
        require(not re.search(r"TODO|YOUR_EMAIL|example\.com", text), f"Placeholder in {page.name}")
        parser = Links()
        parser.feed(text)
        pages[page.name] = parser
    for name, parser in pages.items():
        for link in parser.links:
            url = urlsplit(link)
            if url.scheme:
                require(url.scheme in ("https", "mailto"), f"Unsafe support link: {link}")
                continue
            target = url.path or name
            require((site / target).is_file(), f"Broken support link: {link}")
            if url.fragment:
                require(target in pages and url.fragment in pages[target].ids, f"Broken anchor: {link}")
    print(f"Release metadata passed: 3 tips, {len(strings['strings'])} bilingual strings, {len(icons)} icon sets, support pages.")


def check_app(app):
    require(app.is_dir(), f"Missing app bundle: {app}")
    main_info = plist(app / "Info.plist")
    require(main_info["CFBundleIdentifier"] == "org.bortongo.PetIsland", "Unexpected app ID")
    require(main_info.get("ITSAppUsesNonExemptEncryption") is False, "Encryption flag absent from bundle")
    extensions = list((app / "PlugIns").glob("*.appex"))
    require(len(extensions) == 1, "Expected one widget/Live Activity extension")
    for bundle in [app, *extensions]:
        for language in ("en", "ru"):
            require((bundle / f"{language}.lproj" / "Localizable.strings").is_file(),
                    f"{bundle.name}: missing {language} strings")
        require(plist(bundle / "PrivacyInfo.xcprivacy") == plist(ROOT / "SharedResources/PrivacyInfo.xcprivacy"),
                f"Incorrect privacy manifest in {bundle.name}")
        info = plist(bundle / "Info.plist")
        for key in ("CFBundleVersion", "CFBundleShortVersionString"):
            require(info[key] == main_info[key], f"Version mismatch in {bundle.name}")
    require(not list(app.rglob("*.storekit")), "Local StoreKit config in app bundle")
    require(not list(app.rglob("*.xctest")), "Tests in release bundle")
    require((app / "Assets.car").is_file(), "Missing asset catalog")
    print(f"Release bundle passed: {app.name}, matching app/extension versions and privacy manifests; no test purchases bundled.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, help="Optional built Release .app")
    args = parser.parse_args()
    check_sources()
    if args.app:
        check_app(args.app)
