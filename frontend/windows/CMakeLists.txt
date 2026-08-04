# Project-level configuration for Windows desktop build.
cmake_minimum_required(VERSION 3.14)
project(pcos_frontend LANGUAGES CXX)

# Explicitly opt in to modern CMake policies.
if(POLICY CMP0091)
  cmake_policy(SET CMP0091 NEW)
endif()

# Configuration provided via --dart-define flags.
set(DART_DEFINES "" CACHE STRING "Dart defines")

# Set build type to Release by default.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Choose the type of build." FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS "Debug" "Release" "Profile")
endif()

# Global options
option(BUILD_SHARED_LIBS "Build using shared libraries" OFF)

# Include the Flutter CMake library.
add_subdirectory(flutter)

# Application build configuration.
add_subdirectory(runner)
