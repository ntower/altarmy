-- Golden: one character's bags and bank as the addon's containers v4 save them (DataStoreContainers),
-- written by spec/Data/DataStoreContainers_spec.lua ("writes the golden holdings") and read by the site's
-- altarmy.py (site/tests/test_altarmy.py). A soulbound copy's slot says `bound`.
AltArmyTBC_Data = {
["Characters"] = {
["Classic Beta PvE"] = {
["Player-4395-00000001"] = {
["guid"] = "Player-4395-00000001",
["name"] = "Holder",
["realm"] = "Classic Beta PvE",
["faction"] = "Horde",
["classFile"] = "MAGE",
["level"] = 30,
["bagsScannedAt"] = 1790725000,
["bankScannedAt"] = 1790726000,
["Containers"] = {
[0] = {
["numSlots"] = 4,
["links"] = {
[1] = "|Hitem:2589::::::::30:::::|h[Linen Cloth]|h",
[2] = "|Hitem:2140::::::::30:::::|h[Carving Knife]|h",
[4] = "|Hitem:2589::::::::30:::::|h[Linen Cloth]|h",
},
["items"] = {
[1] = { ["itemID"] = 2589, ["count"] = 20 },
[2] = { ["itemID"] = 2140, ["count"] = 1, ["bound"] = true },
[4] = { ["itemID"] = 2589, ["count"] = 5 },
},
},
[-1] = {
["numSlots"] = 2,
["links"] = {
[1] = "|Hitem:2770::::::::30:::::|h[Copper Ore]|h",
},
["items"] = {
[1] = { ["itemID"] = 2770, ["count"] = 10 },
},
},
},
},
},
},
}
