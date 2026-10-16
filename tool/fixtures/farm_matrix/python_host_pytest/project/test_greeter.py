from greeter import greet


def test_greets_by_name():
    assert greet("Ada") == "Hello, Ada!"
