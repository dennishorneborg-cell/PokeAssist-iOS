param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDirectory,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$species = Import-Csv (Join-Path $SourceDirectory 'pokemon_species.csv')
$names = Import-Csv (Join-Path $SourceDirectory 'pokemon_species_names.csv')
$shiny = Get-Content -Raw (Join-Path $SourceDirectory 'shiny_pokemon.json') | ConvertFrom-Json -AsHashtable
$goPokemon = Get-Content -Raw (Join-Path $SourceDirectory 'pokemon.json') | ConvertFrom-Json
$forms = Get-Content -Raw (Join-Path $SourceDirectory 'forms.json') | ConvertFrom-Json

$namesBySpeciesAndLanguage = @{}
foreach ($name in $names) {
    $namesBySpeciesAndLanguage["$($name.pokemon_species_id):$($name.local_language_id)"] = $name.name
}

$costumeFormIds = [System.Collections.Generic.HashSet[int]]::new()
foreach ($form in $forms) {
    if ($form.isCostume -eq $true) {
        [void]$costumeFormIds.Add([int]$form.formId)
    }
}

$costumeSpeciesIds = [System.Collections.Generic.HashSet[int]]::new()
foreach ($pokemon in $goPokemon) {
    foreach ($formId in @($pokemon.forms)) {
        if ($costumeFormIds.Contains([int]$formId)) {
            [void]$costumeSpeciesIds.Add([int]$pokemon.pokedexId)
            break
        }
    }
}

# The upstream form feed does not currently map every historical costume back
# to its species. Keep small, source-backed overrides explicit and reviewable.
# Hoothoot's New Year's outfit can also evolve into an outfitted Noctowl:
# https://pokemongo.com/news/new-years-2023
foreach ($id in @(163, 164)) {
    [void]$costumeSpeciesIds.Add($id)
}

# PokéAPI exposes legendary and mythical flags, but not Ultra Beasts separately.
# These National Pokédex IDs are therefore intentionally explicit and reviewable.
$ultraBeastIds = [System.Collections.Generic.HashSet[int]]::new()
foreach ($id in @(793, 794, 795, 796, 797, 798, 799, 803, 804, 805, 806)) {
    [void]$ultraBeastIds.Add($id)
}

$entries = foreach ($row in $species) {
    $id = [int]$row.id
    if ($id -gt 1025) { continue }

    $englishName = $namesBySpeciesAndLanguage["${id}:9"]
    $germanName = $namesBySpeciesAndLanguage["${id}:6"]
    if ([string]::IsNullOrWhiteSpace($englishName)) { continue }
    if ([string]::IsNullOrWhiteSpace($germanName)) { $germanName = $englishName }

    $rarity = if ($ultraBeastIds.Contains($id)) {
        'ultraBeast'
    } elseif ($row.is_mythical -eq '1') {
        'mythical'
    } elseif ($row.is_legendary -eq '1') {
        'legendary'
    } else {
        'standard'
    }

    [ordered]@{
        id = $id
        englishName = $englishName
        germanName = $germanName
        rarity = $rarity
        shinyReleased = $shiny.ContainsKey([string]$id)
        hasEventCostumeVariant = $costumeSpeciesIds.Contains($id)
    }
}

$snapshot = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    sources = @(
        'https://github.com/PokeAPI/pokeapi/tree/master/data/v2/csv',
        'https://pogoapi.net/api/v1/shiny_pokemon.json',
        'https://github.com/WatWowMap/pogo-data-api/tree/main/data/v1',
        'https://pokemongo.com/news/new-years-2023'
    )
    species = @($entries)
}

$parent = Split-Path -Parent $OutputPath
if ($parent) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

$snapshot | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 $OutputPath
