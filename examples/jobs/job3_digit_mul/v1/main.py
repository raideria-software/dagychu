import json
import sys


def main() -> None:
    payload = json.loads(sys.stdin.read() or "{}")
    n = int(payload.get("number"))
    digits = [int(c) for c in str(abs(n))]
    if len(digits) == 1:
        result = n
    else:
        result = digits[0] * digits[1]
    print(json.dumps({"result": result}))


if __name__ == "__main__":
    main()
