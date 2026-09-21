import json
import unicodedata
from pathlib import Path


CATALOG_PATH = Path("PokeAssist/Resources/pokemon_catalog.json")


def normalize(value: str) -> str:
    value = value.replace("♀", " female ").replace("♂", " male ").casefold()
    return "".join(
        character
        for character in unicodedata.normalize("NFKD", value)
        if character.isalnum() and not unicodedata.combining(character)
    )


catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8-sig"))
species = catalog["species"]
ids = [entry["id"] for entry in species]

assert catalog["schemaVersion"] == 1
assert len(species) >= 1025
assert len(ids) == len(set(ids))
assert all(entry["englishName"] and entry["germanName"] for entry in species)
assert any(entry["rarity"] == "legendary" for entry in species)
assert any(entry["rarity"] == "mythical" for entry in species)
assert any(entry["rarity"] == "ultraBeast" for entry in species)
assert any(entry["hasEventCostumeVariant"] for entry in species)

by_id = {entry["id"]: entry for entry in species}
assert by_id[77]["germanName"] == "Ponita"
assert by_id[150]["rarity"] == "legendary"
assert by_id[151]["rarity"] == "mythical"
assert by_id[793]["rarity"] == "ultraBeast"
assert by_id[25]["shinyReleased"] is True
assert by_id[25]["hasEventCostumeVariant"] is True
assert by_id[163]["hasEventCostumeVariant"] is True
assert by_id[164]["hasEventCostumeVariant"] is True

aliases: dict[str, int] = {}
for entry in species:
    for name in (entry["englishName"], entry["germanName"]):
        key = normalize(name)
        assert key not in aliases or aliases[key] == entry["id"], (
            name,
            aliases[key],
            entry["id"],
        )
        aliases[key] = entry["id"]


def match_species(value: str) -> int | None:
    normalized = normalize(value)
    if normalized in aliases:
        return aliases[normalized]

    for alias in sorted(aliases, key=lambda item: (-len(item), item)):
        suffix = normalized.removeprefix(alias) if normalized.startswith(alias) else ""
        if suffix and len(suffix) <= 8 and all(character.isnumeric() or character in "oil" for character in suffix):
            return aliases[alias]
    return None


# Regression coverage for numeric IV annotations and longest-prefix matching.
assert match_species("Hoothoot⁵⁶㉘") == 163
assert match_species("Hoothoot O") == 163
assert match_species("Mewtwo 42") == 150
assert match_species("Mewtwo buddy") is None

print(f"Validated {len(species)} species and {len(aliases)} localized aliases")
