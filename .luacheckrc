std = "luajit"
max_line_length = false
globals = { "G_reader_settings" }
files["tests/native.lua"] = { globals = { "G_defaults" } }
