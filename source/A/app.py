"""Component A: a tiny Python service stub.

Stands in for a real component so the build/test/package wiring has something
to act on. The point of this repo is the Kosli + CI orchestration, not A itself.
"""


def greet(name):
    """Return a greeting for the given name."""
    return f"A says hello, {name}"


if __name__ == "__main__":
    print(greet("world"))
