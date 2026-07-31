cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

apply_standard_settings(${BINARY_NAME})

target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

set(V2BOXKIT_NATIVE_DIR "${CMAKE_SOURCE_DIR}/native/windows/x64")
set(V2BOXKIT_NATIVE_LIBRARIES
  "${V2BOXKIT_NATIVE_DIR}/libXray.dll"
  "${V2BOXKIT_NATIVE_DIR}/wintun.dll"
)

foreach(NATIVE_LIBRARY ${V2BOXKIT_NATIVE_LIBRARIES})
  if(NOT EXISTS "${NATIVE_LIBRARY}")
    message(FATAL_ERROR
      "Missing ${NATIVE_LIBRARY}. Run tool/fetch_windows_runtime.ps1 before building.")
  endif()
  add_custom_command(
    TARGET ${BINARY_NAME}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${NATIVE_LIBRARY}"
      "$<TARGET_FILE_DIR:${BINARY_NAME}>"
    VERBATIM
  )
endforeach()

add_dependencies(${BINARY_NAME} flutter_assemble)
