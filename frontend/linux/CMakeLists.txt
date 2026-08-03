cmake_minimum_required(VERSION 3.14)
project(pcos_frontend LANGUAGES CXX)

set(BINARY_NAME "pcos_frontend")
set(APPLICATION_ID "com.pcos.app")

add_subdirectory(flutter)

add_executable(${BINARY_NAME} "main.cc" "my_application.cc")
target_compile_features(${BINARY_NAME} PUBLIC cxx_std_14)

pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
target_link_libraries(${BINARY_NAME} PRIVATE flutter PkgConfig::GTK)

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}/bin")
install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${CMAKE_INSTALL_PREFIX}/lib" COMPONENT Runtime)
install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${CMAKE_INSTALL_PREFIX}/lib" COMPONENT Runtime)
