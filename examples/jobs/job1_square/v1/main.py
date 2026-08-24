from jobs._lib.dagychu_stdio import read_stdin_json, write_stdout_json


def main() -> None:
    payload = read_stdin_json()
    n = int(payload.get("number", 1))
    if n < 1 or n > 10:
        raise ValueError("number must be in range 1..10")
    write_stdout_json({"result": n * n})


if __name__ == "__main__":
    main()
