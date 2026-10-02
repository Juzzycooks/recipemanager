import os, shutil, subprocess, unittest


@unittest.skipUnless(shutil.which("node"), "node is not installed")
class CookJs(unittest.TestCase):
    def test_cook_logic(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        result = subprocess.run(["node", os.path.join(root, "tests", "test_cook.js")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_unit_conversion(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        result = subprocess.run(["node", os.path.join(root, "tests", "test_unitconv.js")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
