"""Remove the one-time shared-registration secret from generated Synapse YAML.

The official image generator may place this high-value bootstrap credential in
/data/homeserver.yaml. The closed profile does not use shared-secret
registration, so bootstrap calls this script immediately after generation.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import tempfile


CONFIG_PATH = Path("/data/homeserver.yaml")
SECRET_SETTING = re.compile(
    r"^\s*(?:registration_shared_secret|registration_shared_secret_path)\s*:"
)


def main() -> None:
    original = CONFIG_PATH.read_text(encoding="utf-8")
    retained = [
        line
        for line in original.splitlines(keepends=True)
        if not SECRET_SETTING.match(line)
    ]
    scrubbed = "".join(retained)

    if scrubbed == original:
        return

    descriptor, temporary_name = tempfile.mkstemp(
        prefix="homeserver.yaml.", suffix=".tmp", dir=CONFIG_PATH.parent
    )
    temporary_path = Path(temporary_name)
    try:
        if hasattr(os, "fchmod"):
            os.fchmod(descriptor, 0o600)
        stream = os.fdopen(descriptor, "w", encoding="utf-8", newline="")
        descriptor = -1
        with stream:
            stream.write(scrubbed)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_path, CONFIG_PATH)
        if os.name == "posix":
            directory_descriptor = os.open(CONFIG_PATH.parent, os.O_RDONLY)
            try:
                os.fsync(directory_descriptor)
            finally:
                os.close(directory_descriptor)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        temporary_path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
