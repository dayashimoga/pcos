cmake_minimum_required(VERSION 3.14)
project(pcos_frontend LANGUAGES CXX)

set(BINARY_NAME "pcos_frontend")
set(APPLICATION_ID "com.pcos.app")

cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

add_subdirectory(flutter)

add_executable(${BINARY_NAME} WIN32 "runner/main.cpp" "runner/flutter_window.cpp" "runner/utils.cpp" "runner/win32_window.cpp")
target_compile_features(${BINARY_NAME} PUBLIC cxx_std_17)
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
