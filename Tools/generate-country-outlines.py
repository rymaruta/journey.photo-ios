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


def simplify(points, tolerance=0.025):
    """Ramer-Douglas-Peucker simplification, preserving small islands."""
    if len(points) < 5:
        return points
    keep = {0, len(points) - 1}
    stack = [(0, len(points) - 1)]
    limit = tolerance * tolerance
    while stack:
        lo, hi = stack.pop()
        x, y = points[lo][:2]
        dx, dy = points[hi][0] - x, points[hi][1] - y
        denominator = dx * dx + dy * dy
        best, index = -1.0, -1
        for i in range(lo + 1, hi):
            px, py = points[i][0] - x, points[i][1] - y
            t = max(0.0, min(1.0, (px * dx + py * dy) / denominator)) if denominator else 0.0
            distance = (px - t * dx) ** 2 + (py - t * dy) ** 2
            if distance > best:
                best, index = distance, i
        if best > limit:
            keep.add(index)
            stack.extend([(lo, index), (index, hi)])
    return [points[i] for i in sorted(keep)]


def normalize_ring(points):
    result = [[round(lon, 4), round(lat, 4)] for lon, lat, *_ in simplify(points)]
    if len(result) < 4:
        return []
    if result[0] != result[-1]:
        result.append(result[0])
    return result if len(set(map(tuple, result[:-1]))) >= 3 else []


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
        # Retain interior holes for even-odd rendering and land lookup.
        rings = [normalized for polygon in polygons
                 for ring in polygon
                 for normalized in [normalize_ring(ring)] if normalized]
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
