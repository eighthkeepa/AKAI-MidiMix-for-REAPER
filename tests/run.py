import sys
import lupa

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
src = open("tests/test_main.lua", encoding="utf-8").read()
fails = lua.execute(src)
sys.exit(1 if fails else 0)
