from contextlib import contextmanager
import fcntl
import tempfile
from pathlib import Path


@contextmanager
def benchmark_lock():
    with (Path(tempfile.gettempdir()) / "floater-model-benchmark.lock").open("a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)
