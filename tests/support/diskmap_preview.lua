local name = os.getenv("DISKMAP_FIXTURE") or "hero"
return require("tests.support.diskmap_fixtures").new():render(name)
