import unittest

from greeter import greet


class GreetTest(unittest.TestCase):
    def test_greets_by_name(self):
        self.assertEqual(greet("Ada"), "Hello, Ada!")

    def test_legacy_banner(self):
        # Known broken before this roadmap: the banner was never implemented.
        self.assertEqual(greet(""), "Hello, stranger!")


if __name__ == "__main__":
    unittest.main()
