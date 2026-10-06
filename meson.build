project('singularity-usage', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-usage"', language: 'c')
subdir('po')

gtk_dep   = dependency('gtk4')
gee_dep   = dependency('gee-0.8')
posix_dep = meson.get_compiler('vala').find_library('posix')
m_dep     = meson.get_compiler('c').find_library('m', required: false)

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

executable('singularity-usage',
  files('src/scanner.vala', 'src/rings.vala', 'src/window.vala', 'src/app.vala'),
  dependencies: [gtk_dep, gee_dep, posix_dep, m_dep, libsingularity_dep],
  install: true
)

shared_module('singularity-usage-widget',
  files('widget/free_space_widget.vala'),
  dependencies: [gtk_dep, gee_dep, m_dep, dependency('gio-unix-2.0'), libsingularity_dep],
  install: true,
  install_dir: get_option('libdir') / 'singularity' / 'widgets'
)

install_data('widget/dev.sinty.usage.free-space.widget',
  install_dir: get_option('datadir') / 'singularity' / 'widgets'
)

scanner_test = executable('usage-test',
  files('src/scanner.vala', 'tests/scanner_test.vala'),
  dependencies: [gee_dep, posix_dep, dependency('gio-2.0')],
)
test('usage', scanner_test)

install_data('data/dev.sinty.usage.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/icons/dev.sinty.usage.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
