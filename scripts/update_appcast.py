#!/usr/bin/env python3
"""Insert a Sparkle appcast <item> for a new OnTime release."""

from __future__ import annotations

import re
import sys
from datetime import datetime, timezone


def update_appcast(
    appcast_path: str,
    version: str,
    build_number: str,
    zip_url: str,
    zip_size: str,
    ed_signature: str,
    release_notes: str = "",
) -> None:
    with open(appcast_path, "r", encoding="utf-8") as f:
        content = f.read()

    version = version.lstrip("v")
    pub_date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")

    if not release_notes:
        release_notes = (
            f"<h2>OnTime {version}</h2>"
            "<ul><li>Maintenance and improvements.</li></ul>"
        )

    if re.search(rf'sparkle:shortVersionString="{re.escape(version)}"', content):
        print(f"Version {version} already exists in {appcast_path}. Skipping.")
        return

    item_xml = f"""
    <item>
      <title>Version {version}</title>
      <link>https://github.com/RamiruWanigathunga/OnTime/releases/tag/v{version}</link>
      <sparkle:version>{build_number}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <description><![CDATA[
        {release_notes}
      ]]></description>
      <pubDate>{pub_date}</pubDate>
      <enclosure
        url="{zip_url}"
        sparkle:version="{build_number}"
        sparkle:shortVersionString="{version}"
        sparkle:edSignature="{ed_signature}"
        length="{zip_size}"
        type="application/octet-stream" />
    </item>
"""

    # Drop the empty-feed comment on first real item.
    content = re.sub(
        r"\s*<!-- No items yet\.[^>]*-->\s*",
        "\n",
        content,
        count=1,
    )

    marker = "<language>en</language>"
    if marker not in content:
        raise SystemExit(f"Could not find {marker!r} in {appcast_path}")

    new_content = content.replace(marker, f"{marker}\n{item_xml}", 1)
    with open(appcast_path, "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"Updated {appcast_path} for {version} (build {build_number}).")


if __name__ == "__main__":
    if len(sys.argv) < 7:
        print(
            "Usage: update_appcast.py <appcast.xml> <version> <build> "
            "<zip_url> <zip_size> <ed_signature> [release_notes_html]",
            file=sys.stderr,
        )
        sys.exit(1)

    notes = sys.argv[7] if len(sys.argv) > 7 else ""
    update_appcast(
        sys.argv[1],
        sys.argv[2],
        sys.argv[3],
        sys.argv[4],
        sys.argv[5],
        sys.argv[6],
        notes,
    )
