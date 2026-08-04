# Flutter configuration for Windows desktop build.
cmake_minimum_required(VERSION 3.14)

set(EPHEMERAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ephemeral")

# Configuration provided via --dart-define flags.
set(DART_DEFINES "" CACHE STRING "Dart defines")

# Generated code configuration.
set(FLUTTER_MANAGED_DIR "${EPHEMERAL_DIR}/flutter_managed")

# Include the generated CMake configuration.
include("${FLUTTER_MANAGED_DIR}/generated_config.cmake" OPTIONAL)

# Set build properties.
set(FLUTTER_EPHEMERAL_DIR "${EPHEMERAL_DIR}" PARENT_SCOPE)

# Add the Flutter library dependencies.
add_library(flutter INTERFACE)
target_include_directories(flutter INTERFACE
  "${EPHEMERAL_DIR}"
)
target_link_libraries(flutter INTERFACE
  "${EPHEMERAL_DIR}/flutter_windows.dll.lib"
)

# Set target properties for plugin builds.
add_library(flutter_wrapper_plugin STATIC
  "${FLUTTER_MANAGED_DIR}/flutter_plugin_registrant.cc"
)
target_include_directories(flutter_wrapper_plugin PUBLIC
  "${EPHEMERAL_DIR}"
)
target_link_libraries(flutter_wrapper_plugin PUBLIC
  flutter
)
