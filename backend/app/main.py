"""
Compatibility entrypoint.

Some local scripts may run `uvicorn app.main:app` while others run `uvicorn main:app`.
To avoid diverging behavior and path bugs, always expose the root backend app here.
"""

from main import app  # noqa: F401