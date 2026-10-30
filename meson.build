project('lite', 'c',
  version : '1.11',
  default_options : ['c_std=gnu11', 'optimization=3', 'warning_level=1'])

add_project_arguments('-DLUA_USE_POSIX', '-fno-strict-aliasing', language : 'c')

sources = run_command('find', 'src', '-name', '*.c', check : true).stdout().strip().split('\n')

deps = [dependency('sdl2'), meson.get_compiler('c').find_library('m', required : false)]

# Build into the repo root so the editor finds ./data next to the binary.
executable('lite', sources,
  include_directories : include_directories('src'),
  dependencies : deps,
  install : false)

# Copy runtime data next to the binary on every build.
custom_target('copy-data',
  output : 'data.stamp',
  command : ['sh', '-c', 'rm -rf "$0/data" && cp -r "$1/data" "$0/data" && touch "$2"', meson.project_build_root(), meson.project_source_root(), '@OUTPUT@'],
  build_always_stale : true,
  build_by_default : true)
