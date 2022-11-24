local _2afile_2a = "test/fnl/ctags/main-test.fnl"
local _2amodule_name_2a = "ctags.main-test"
local _2amodule_2a
do
  package.loaded[_2amodule_name_2a] = {}
  _2amodule_2a = package.loaded[_2amodule_name_2a]
end
local _2amodule_locals_2a
do
  _2amodule_2a["aniseed/locals"] = {}
  _2amodule_locals_2a = (_2amodule_2a)["aniseed/locals"]
end
do
  local tests_23_auto = ((_2amodule_2a)["aniseed/tests"] or {})
  local function _1_(t)
    return t["="](1, 1, "1 should equal 1, I hope!")
  end
  tests_23_auto["something-simple"] = _1_
  _2amodule_2a["aniseed/tests"] = tests_23_auto
end
return _2amodule_2a