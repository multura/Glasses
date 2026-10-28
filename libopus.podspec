Pod::Spec.new do |s|
  s.name = 'libopus'
  s.version = '1.1'
  s.summary = 'Opus audio codec'
  s.homepage = 'https://opus-codec.org/'
  s.license = { :type => 'BSD', :file => 'COPYING' }
  s.author = { 'Xiph.Org Foundation' => 'team@xiph.org' }
  s.source = { :http => 'https://downloads.xiph.org/releases/opus/opus-1.1.tar.gz' }
  s.prepare_command = <<-CMD
    cat >src/config.h <<CONFIG_H
    #define HAVE_DLFCN_H 1
    #define HAVE_INTTYPES_H 1
    #define HAVE_LRINT 1
    #define HAVE_LRINTF 1
    #define HAVE_MEMORY_H 1
    #define HAVE_STDINT_H 1
    #define HAVE_STDLIB_H 1
    #define HAVE_STRING_H 1
    #define HAVE_SYS_STAT_H 1
    #define HAVE_SYS_TYPES_H 1
    #define HAVE_UNISTD_H 1
    #define OPUS_BUILD
    #define STDC_HEADERS 1
    #define VAR_ARRAYS 1
    CONFIG_H
  CMD
  s.source_files = [
    'src/config.h',
    'include/*.h',
    'silk/*.{c,h}',
    'celt/*.{c,h}',
    'src/opus.c',
    'src/opus_decoder.c',
    'src/opus_encoder.c',
    'src/opus_multistream.c',
    'src/opus_multistream_encoder.c',
    'src/opus_multistream_decoder.c',
    'src/repacketizer.c',
    'src/analysis.c',
    'src/mlp.c',
    'src/mlp_data.c',
    'src/opus_private.h',
    'src/analysis.h',
    'src/mlp.h',
    'src/tansig_table.h',
    'silk/float',
    'celt/x86'
  ]
  s.public_header_files = 'include/**/*.h'
  s.header_mappings_dir = 'include'
  s.compiler_flags = '-w -DHAVE_CONFIG_H=1 -DFLOATING_POINT'
  s.exclude_files = 'celt/opus_custom_demo.c'
  s.xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_ROOT}/libopus" "${PODS_ROOT}/libopus/src" "${PODS_ROOT}/libopus/silk" "${PODS_ROOT}/libopus/include" "${PODS_ROOT}/libopus/celt"'
  }
  s.requires_arc = false
  s.static_framework = true
  s.ios.deployment_target = '15.0'
end
