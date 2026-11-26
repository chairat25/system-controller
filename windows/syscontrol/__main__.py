import sys

if __name__ == "__main__":
    if "--headless" in sys.argv:
        from .headless import main
        sys.exit(main([arg for arg in sys.argv[1:] if arg != "--headless"]))
    from .app import main
    sys.exit(main())
