#!/usr/bin/env python3
"""Regenerate bundled share-card coastlines from Natural Earth 1:10m.

Usage: python3 Tools/generate-country-outlines.py
Source: Natural Earth public-domain ne_10m_admin_0_countries GeoJSON.
Requires network access when regenerating; no third-party Python packages.
"""
import json
import pathlib
import urllib.request

SOURCE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_0_countries.geojson"
DEST = pathlib.Path(__file__).resolve().parents[1] / "Sources/JourneyPhoto/Resources/country-outlines.json"


def normalize_ring(points):
    # 1:10m vertices retained at 4 decimal places (~11m at the equator).
    result = []
    for lon, lat, *_ in points:
        pair = [round(lon, 4), round(lat, 4)]
        if not result or pair != result[-1]:
            result.append(pair)
    if len(result) >= 3 and result[0] != result[-1]:
        result.append(result[0])
    return result if len(result) >= 4 else []


def main():
    request = urllib.request.Request(SOURCE, headers={"User-Agent": "JourneyPhoto-map-generator/1.0"})
    with urllib.request.urlopen(request, timeout=90) as response:
        geojson = json.load(response)
    if geojson.get("type") != "FeatureCollection":
        raise ValueError("Expected Natural Earth FeatureCollection")
    countries = []
    for feature in geojson["features"]:
        geometry = feature.get("geometry") or {}
        kind = geometry.get("type")
        coords = geometry.get("coordinates") or []
        if kind == "Polygon":
            polygons = [coords]
        elif kind == "MultiPolygon":
            polygons = coords
        else:
            continue
        # Only exterior rings. Holes are not compatible with the existing
        # renderer's point-in-country logic and must not be treated as land.
        rings = [ring for polygon in polygons if polygon
                 for ring in [normalize_ring(polygon[0])] if ring]
        if rings:
            properties = feature.get("properties") or {}
            countries.append({"n": properties.get("ADMIN") or properties.get("NAME") or "Unknown", "r": rings})
    if len(countries) < 150:
        raise ValueError(f"Unexpectedly few countries: {len(countries)}")
    payload = json.dumps(countries, ensure_ascii=False, separators=(",", ":"))
    DEST.write_text(payload + "\n", encoding="utf-8")
    print(f"Wrote {len(countries)} countries to {DEST} ({len(payload):,} bytes)")


if __name__ == "__main__":
    main()
