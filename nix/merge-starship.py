"""Merge Starship presets in order, with local configuration taking precedence."""
import sys
import toml


def merge(target, source):
    for key, value in source.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            merge(target[key], value)
        else:
            target[key] = value
    return target


def main():
    result = {}
    for path in sys.argv[1:-1]:
        merge(result, toml.load(path))
    result.get("python", {}).pop("format", None)
    with open(sys.argv[-1], "w") as output:
        toml.dump(result, output)


if __name__ == "__main__":
    main()
