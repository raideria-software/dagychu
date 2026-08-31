import sys
from pathlib import Path

_jobs_root = Path(__file__).resolve().parent.parent.parent
_parent = _jobs_root.parent
for _p in (str(_jobs_root), str(_parent)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

try:
    from jobs.demo_orders_transform.v1.main import main
except ImportError:
    from demo_orders_transform.v1.main import main

if __name__ == "__main__":
    main()
