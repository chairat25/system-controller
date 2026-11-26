"""Entry point for PyInstaller (a package's __main__ cannot be the script)."""
import sys

from syscontrol.app import main

if __name__ == "__main__":
    sys.exit(main())
