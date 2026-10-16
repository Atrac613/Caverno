"""Tiny command-line greeter."""

import argparse


def greet(name: str) -> str:
    return f"Hello, {name}!"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Print a greeting.")
    parser.add_argument("name", nargs="?", default="world")
    args = parser.parse_args(argv)
    print(greet(args.name))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
