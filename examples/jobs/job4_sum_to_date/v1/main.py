import json
import sys
from datetime import date, timedelta


def main() -> None:
    payload = json.loads(sys.stdin.read() or "{}")
    left = int(payload.get("left"))
    right = int(payload.get("right"))
    day_of_year = left + right
    year = date.today().year
    result_date = date(year, 1, 1) + timedelta(days=day_of_year - 1)
    print(json.dumps({"result": day_of_year, "date": result_date.isoformat()}))


if __name__ == "__main__":
    main()
