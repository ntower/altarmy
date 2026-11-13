"""Unit tests for scripts/generate-writs.py. Run: python -m unittest scripts/test_generate_writs.py"""
import csv
import importlib.util
import os
import sqlite3
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("generate_writs", os.path.join(HERE, "generate-writs.py"))
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)


def write(dirname, table, header, rows):
    path = os.path.join(dirname, table + ".csv")
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    return path


class MatchTest(unittest.TestCase):
    OUTPUTS = {
        3391: "Elixir of Ogre Strength", 9224: "Potion of Demon Slaying", 3972: "Pearl-handled Dagger",
        6861: "Gyromatic Micro-Adjustor", 4383: "Moonsight Rifle", 9366: "Golden Scale Gauntlets",
        217273: "Golden Scale Gauntlets", 2568: "Linen Cloak", 2569: "Woolen Cloak",
    }

    def test_normalize_drops_case_spaces_and_punctuation(self):
        self.assertEqual("pearlhandleddagger", gen.normalize("Pearl-Handled Dagger"))
        self.assertEqual("potionofdemonslaying", gen.normalize("Potion of Demonslaying"))

    def test_levenshtein(self):
        self.assertEqual(0, gen.levenshtein("abc", "abc"))
        self.assertEqual(1, gen.levenshtein("adjuster", "adjustor"))
        self.assertEqual(2, gen.levenshtein("ogresstrength", "ogrestrength") + 1)
        self.assertEqual(3, gen.levenshtein("kitten", "sitting"))

    def test_exact_after_normalising(self):
        self.assertEqual([9224], gen.match_candidates("Potion of Demonslaying", self.OUTPUTS))
        self.assertEqual([3972], gen.match_candidates("Pearl-Handled Dagger", self.OUTPUTS))

    def test_nearest_within_two_edits(self):
        self.assertEqual([3391], gen.match_candidates("Elixir of Ogre's Strength", self.OUTPUTS))
        self.assertEqual([6861], gen.match_candidates("Gyromatic Micro-Adjuster", self.OUTPUTS))

    def test_every_item_of_the_name(self):
        self.assertEqual([9366, 217273], gen.match_candidates("Golden Scale Gauntlets", self.OUTPUTS))

    def test_nothing_close(self):
        self.assertEqual([], gen.match_candidates("Runecloth Bag", self.OUTPUTS))

    def test_tie_between_names_fails(self):
        with self.assertRaises(SystemExit):
            gen.match_candidates("Lonen Cloak", {1: "Linen Cloak", 2: "Loner Cloak"})


ITEM_COLS = "id, name, buy_price, buy_count, bonding, stack_size"


class BuildTest(unittest.TestCase):
    """A tiny Forever: two writs, a robe made from a bolt made from cloth, thread sold by a vendor."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = self.tmp.name
        self.db = os.path.join(d, "game.sqlite")
        db = sqlite3.connect(self.db)
        db.executescript(
            "CREATE TABLE items (game_version, id, name, buy_price, buy_count, bonding, stack_size);"
            "CREATE TABLE vendor_items (game_version, item_id);"
            "CREATE TABLE recipes (game_version, id, spell_id, name, skill_name, output_item_id, output_count,"
            " skill_line, kind);"
            "CREATE TABLE recipe_reagents (game_version, recipe_id, item_id, count, slot);"
        )
        items = [
            (264047, "Craftsman's Writ: Lesser Wizard's Robe", 5, 1, 0, 1),
            (264037, "Craftsman's Writ: Crafted Solid Shot", 5, 1, 0, 1),
            (4316, "Lesser Wizard's Robe", 0, 1, 2, 1),
            (4305, "Bolt of Silk Cloth", 0, 1, 0, 20),
            (4306, "Silk Cloth", 0, 1, 0, 20),
            (2321, "Fine Thread", 100, 1, 0, 20),
            (3182, "Spider's Silk", 0, 1, 0, 10),
            (8069, "Crafted Solid Shot", 0, 1, 0, 200),
            (3860, "Mithril Bar", 0, 1, 0, 20),
            (18240, "Ogre Tannin", 0, 1, 1, 1),
            (99, "Test Thing", 0, 1, 0, 1),
        ]
        db.executemany("INSERT INTO items VALUES ('forever', ?, ?, ?, ?, ?, ?)", items)
        db.execute("INSERT INTO items VALUES ('tbc', 2321, 'Fine Thread', 100, 1, 0, 20)")
        db.executemany("INSERT INTO vendor_items VALUES ('forever', ?)", [(2321,), (99,)])
        recipes = [
            (3850, 3850, "Lesser Wizard's Robe", "Tailoring", 4316, 1, 197, "craft"),
            (3839, 3839, "Bolt of Silk Cloth", "Tailoring", 4305, 1, 197, "craft"),
            (3947, 3947, "Crafted Solid Shot", "Engineering", 8069, 200, 202, "craft"),
            (999, 999, "Test Thing", "Test Profession [DNT]", 99, 1, 2777, "craft"),
            (7000, 7000, "Enchant Weapon", "Enchanting", 0, 1, 333, "enchant"),
        ]
        db.executemany("INSERT INTO recipes VALUES ('forever', ?, ?, ?, ?, ?, ?, ?, ?)", recipes)
        reagents = [
            (3850, 4305, 2, 1), (3850, 2321, 2, 0), (3850, 3182, 2, 2),
            (3839, 4306, 4, 0), (3947, 3860, 1, 0), (999, 18240, 1, 0),
        ]
        db.executemany("INSERT INTO recipe_reagents VALUES ('forever', ?, ?, ?, ?)", reagents)
        db.commit()
        db.close()
        self.sparse = write(d, "ItemSparse", ["ID", "StartQuestID", "ItemNameDescriptionID"], [
            [264047, 94247, 14480], [264037, 94237, 14481], [4316, 0, 0],
        ])
        self.labels = write(d, "ItemNameDescription", ["ID", "Description_lang"], [
            [14480, "Journeyman"], [14481, "Expert"], [14482, "Artisan"],
        ])
        gen.WRIT_COUNT, gen.RECIPE_BAND = 2, (1, 10)

    def tearDown(self):
        self.tmp.cleanup()

    def build(self):
        writs, items, vendor, recipes = gen.read_game(self.db)
        sparse = gen.read_rows(self.sparse, {str(i) for i, _ in writs})
        labels = {k: r["Description_lang"] for k, r in gen.read_rows(self.labels).items()}
        return gen.plan_data(writs, items, vendor, recipes, sparse, labels)

    def test_writs_with_quest_tier_rep_and_count(self):
        rows, _, _ = self.build()
        self.assertEqual([
            {"id": 264037, "quest": 94237, "name": "Craftsman's Writ: Crafted Solid Shot",
             "short": "Crafted Solid Shot", "tier": "Expert", "rep": 125, "items": [8069], "count": 200},
            {"id": 264047, "quest": 94247, "name": "Craftsman's Writ: Lesser Wizard's Robe",
             "short": "Lesser Wizard's Robe", "tier": "Journeyman", "rep": 75, "items": [4316], "count": 1},
        ], rows)

    def test_trees_reach_only_what_the_writs_need(self):
        _, items, recipes = self.build()
        self.assertEqual([2321, 3182, 3860, 4305, 4306, 4316, 8069], sorted(items))
        self.assertEqual([3839, 3850, 3947], sorted(recipes))
        self.assertEqual({"name": "Fine Thread", "stack": 20, "vendor": 100, "per": 1}, items[2321])
        self.assertEqual({"name": "Silk Cloth", "stack": 20}, items[4306])
        self.assertEqual([(2321, 2), (4305, 2), (3182, 2)], recipes[3850]["reagents"])  # in slot order
        self.assertEqual(200, recipes[3947]["n"])

    def test_bop_is_marked(self):
        db = sqlite3.connect(self.db)
        db.execute("INSERT INTO recipe_reagents VALUES ('forever', 3947, 18240, 1, 1)")
        db.commit()
        db.close()
        _, items, _ = self.build()
        self.assertEqual({"name": "Ogre Tannin", "stack": 1, "bop": True}, items[18240])

    def test_random_suffix_items_are_marked(self):
        world = os.path.join(self.tmp.name, "mangos.sqlite")
        db = sqlite3.connect(world)
        db.executescript(
            "CREATE TABLE item_template (entry, patch, name, random_property);"
            "INSERT INTO item_template VALUES (4316, 0, 'Lesser Wizard''s Robe', 0);"
            "INSERT INTO item_template VALUES (4316, 5, 'Lesser Wizard''s Robe', 637);"  # a later patch's row
            "INSERT INTO item_template VALUES (4306, 0, 'Silk Cloth', 0);"
            "INSERT INTO item_template VALUES (12345, 0, 'Not In The Trees', 99);"
        )
        db.commit()
        db.close()
        self.assertEqual({4316}, gen.suffixed(world, {4316, 4306, 2321}))
        text, _ = gen.build_module(self.db, "1.60.1.1", self.sparse, self.labels, world)
        self.assertIn("[4316] = { name = \"Lesser Wizard's Robe\", stack = 1, suffix = true },", text)
        self.assertIn('[4306] = { name = "Silk Cloth", stack = 20 },', text)

    def test_module_is_deterministic_and_lua(self):
        text, count = gen.build_module(self.db, "1.60.1.1", self.sparse, self.labels)
        again, _ = gen.build_module(self.db, "1.60.1.1", self.sparse, self.labels)
        self.assertEqual(text, again)
        self.assertEqual(2, count)
        self.assertIn('W.BUILD = "1.60.1.1"', text)
        self.assertIn(
            "    [3850] = { out = 4316, n = 1, prof = \"Tailoring\", name = \"Lesser Wizard's Robe\", reagents = {\n"
            "      { item = 2321, count = 2 }, { item = 4305, count = 2 }, { item = 3182, count = 2 },\n    } },",
            text,
        )
        self.assertIn(
            "    { id = 264047, quest = 94247, tier = \"Journeyman\", rep = 75, items = { 4316 }, count = 1,\n"
            "      name = \"Craftsman's Writ: Lesser Wizard's Robe\",\n      short = \"Lesser Wizard's Robe\" },",
            text,
        )
        self.assertIn("W.REP = { Journeyman = 75, Expert = 125, Artisan = 200 }", text)

    def test_unknown_tier_fails(self):
        write(self.tmp.name, "ItemNameDescription", ["ID", "Description_lang"], [[14480, "Journeyman"]])
        with self.assertRaises(SystemExit):
            self.build()

    def test_unmatched_writ_fails(self):
        db = sqlite3.connect(self.db)
        db.execute("INSERT INTO items VALUES ('forever', 264050, \"Craftsman's Writ: Small Silk Pack\", 5, 1, 0, 1)")
        db.commit()
        db.close()
        gen.WRIT_COUNT = 3
        with self.assertRaises(SystemExit):
            self.build()


if __name__ == "__main__":
    unittest.main()
