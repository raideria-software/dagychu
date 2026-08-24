import json
import sys


def main() -> None:
    payload = json.loads(sys.stdin.read() or "{}")
    n = int(payload.get("number"))
    reversed_n = int(str(n)[::-1])
    print(json.dumps({"result": n + reversed_n}))


if __name__ == "__main__":
    main()
