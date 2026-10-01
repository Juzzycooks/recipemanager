#!/bin/bash
# Builds the App Store slides (iPhone only) from raw simulator captures in raw/ (1206x2622, 9:41 status bar).
#   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./generate.sh
set -euo pipefail
cd "$(dirname "$0")"
swiftc -O frame.swift -o .frame-bin
for size in "iphone-6.9 1320 2868" "iphone-6.5 1284 2778"; do
  set -- $size; dir=$1; W=$2; H=$3; mkdir -p "$dir"
  s() { ./.frame-bin single "raw/$1.png" "$dir/$2.png" $W $H "$3" "$4"; }
  s 02-home              01-home         "Your recipes, beautifully kept"       "Quick picks, collections and your week at a glance"
  s 03-recipe-detail     02-recipe       "Everything on one page"               "Ingredients, steps, ratings and notes, scaled to your servings"
  s 04-cooking           03-cooking      "Cook hands-free, step by step"        "Big text, a screen that stays awake and real kitchen timers"
  s 08-collections       04-collections  "Organise your way"                    "Group recipes into collections for weeknights, slow cooking and more"
  s 09-collection-detail 05-collection   "Every collection, one tap away"       "Browse a collection as a grid of photos"
  s 06-search            06-search       "Find dinner fast"                     "Search by name, ingredient or tag"
  s 07-all-recipes       07-all-recipes  "Your whole library, offline too"      "Browse everything, even without a connection"
  s 10-add               08-add          "Save recipes from anywhere"           "Import from a link, scan a photo or write your own"
  s 11-settings          09-settings     "Make it yours"                        "Light, dark and colour themes"
  s 01-sign-in           10-sign-in      "Your server. Your recipes."           "Free. No ads, no tracking. It talks only to the server you run"
done
rm -f .frame-bin
