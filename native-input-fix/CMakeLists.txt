cmake_minimum_required(VERSION 3.20)
project(IsaacNativeInputFix LANGUAGES CXX)

include(CTest)

if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

add_library(aim_core STATIC
  src/aim_filter.cpp
)
target_include_directories(aim_core PUBLIC src)
target_compile_features(aim_core PUBLIC cxx_std_17)

add_executable(aim_filter_test tests/aim_filter_test.cpp)
target_link_libraries(aim_filter_test PRIVATE aim_core)
target_compile_features(aim_filter_test PRIVATE cxx_std_17)
add_test(NAME aim_filter COMMAND aim_filter_test)

if(WIN32)
  if(NOT MSVC OR NOT CMAKE_SIZEOF_VOID_P EQUAL 4)
    message(FATAL_ERROR "Runtime targets require 32-bit MSVC (-A Win32)")
  endif()

  add_library(azazel_input_hook SHARED
    src/hook.cpp
  )
  target_link_libraries(azazel_input_hook PRIVATE aim_core bcrypt shell32)
  target_compile_definitions(azazel_input_hook PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(azazel_input_hook PRIVATE /W4 /utf-8 /GR- /GS /guard:cf-)

  add_library(bootstp_bridge SHARED
    src/bootstrap.cpp
    bootstp.def
  )
  target_compile_definitions(bootstp_bridge PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(bootstp_bridge PRIVATE /W4 /utf-8 /GR- /GS)
  target_link_libraries(bootstp_bridge PRIVATE shell32)
  set_target_properties(bootstp_bridge PROPERTIES OUTPUT_NAME "bootstp")

  add_executable(proxy_smoke_test tests/proxy_smoke_test.cpp)
  target_compile_definitions(proxy_smoke_test PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(proxy_smoke_test PRIVATE /W4 /utf-8 /GR- /GS)
  target_link_libraries(proxy_smoke_test PRIVATE advapi32)
  add_test(NAME bootstrap_forwarding COMMAND proxy_smoke_test "$<TARGET_FILE:bootstp_bridge>")

  add_executable(bootstrap_fixture tests/bootstrap_fixture.cpp)
  target_compile_definitions(bootstrap_fixture PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(bootstrap_fixture PRIVATE /W4 /utf-8 /GR- /GS)
  target_link_libraries(bootstrap_fixture PRIVATE advapi32 userenv)

  add_executable(IsaacInputInjector src/injector.cpp src/injection.cpp)
  target_compile_definitions(IsaacInputInjector PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(IsaacInputInjector PRIVATE /W4 /utf-8 /GR- /GS)

  add_executable(IsaacInputLauncher WIN32 src/launcher.cpp src/injection.cpp)
  target_compile_definitions(IsaacInputLauncher PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(IsaacInputLauncher PRIVATE /W4 /utf-8 /GR- /GS)

  add_executable(IsaacInputPatcher WIN32 src/patcher.cpp src/injection.cpp)
  target_compile_definitions(IsaacInputPatcher PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(IsaacInputPatcher PRIVATE /W4 /utf-8 /GR- /GS)
  target_link_libraries(IsaacInputPatcher PRIVATE bcrypt shell32 comdlg32)

  add_executable(IsaacInputUnpatcher WIN32 src/patcher.cpp src/injection.cpp)
  target_compile_definitions(IsaacInputUnpatcher PRIVATE INIF_UNINSTALLER UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(IsaacInputUnpatcher PRIVATE /W4 /utf-8 /GR- /GS)
  target_link_libraries(IsaacInputUnpatcher PRIVATE bcrypt shell32 comdlg32)

  add_executable(bootstrap_patcher_test tests/bootstrap_patcher_test.cpp)
  target_compile_definitions(bootstrap_patcher_test PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(bootstrap_patcher_test PRIVATE /W4 /utf-8 /GR- /GS)
  add_test(NAME bootstrap_patcher_roundtrip COMMAND bootstrap_patcher_test
    "$<TARGET_FILE:IsaacInputPatcher>" "$<TARGET_FILE:IsaacInputUnpatcher>"
    "$<TARGET_FILE:bootstrap_fixture>")

  set(PACKAGE_DIR "${CMAKE_BINARY_DIR}/package/IsaacNativeInputFix")
  add_custom_target(package
    COMMAND ${CMAKE_COMMAND} -E make_directory "${PACKAGE_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:bootstp_bridge>" "${PACKAGE_DIR}/bootstp.dll"
    COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:azazel_input_hook>" "${PACKAGE_DIR}/azazel_input_hook.dll"
    COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:proxy_smoke_test>" "${PACKAGE_DIR}/BootstrapProbe.exe"
    COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:IsaacInputInjector>" "${PACKAGE_DIR}/IsaacInputInjector.exe"
    COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:IsaacInputPatcher>" "${PACKAGE_DIR}/IsaacInputPatcher.exe"
    COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:IsaacInputUnpatcher>" "${PACKAGE_DIR}/IsaacInputUnpatcher.exe"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_SOURCE_DIR}/README.md" "${PACKAGE_DIR}/README.md"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_SOURCE_DIR}/LICENSE" "${PACKAGE_DIR}/LICENSE"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_SOURCE_DIR}/THIRD_PARTY_NOTICES.md" "${PACKAGE_DIR}/THIRD_PARTY_NOTICES.md"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_SOURCE_DIR}/docs/deployment-steam-deck.md" "${PACKAGE_DIR}/DEPLOYMENT_STEAM_DECK.md"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_SOURCE_DIR}/docs/deployment-windows.md" "${PACKAGE_DIR}/DEPLOYMENT_WINDOWS.md"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${PACKAGE_DIR}/config"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${PACKAGE_DIR}/tools"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_SOURCE_DIR}/config/diagnostic.ini" "${PACKAGE_DIR}/config/diagnostic.ini"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_SOURCE_DIR}/config/generic-test.ini" "${PACKAGE_DIR}/config/generic-test.ini"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_SOURCE_DIR}/config/tainted-test.ini" "${PACKAGE_DIR}/config/tainted-test.ini"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_SOURCE_DIR}/tools/deck-install.sh" "${PACKAGE_DIR}/tools/deck-install.sh"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_SOURCE_DIR}/tools/deck-inject.sh" "${PACKAGE_DIR}/tools/deck-inject.sh"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_SOURCE_DIR}/tools/deck-collect.sh" "${PACKAGE_DIR}/tools/deck-collect.sh"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_SOURCE_DIR}/tools/deck-uninstall.sh" "${PACKAGE_DIR}/tools/deck-uninstall.sh"
    DEPENDS bootstp_bridge azazel_input_hook aim_filter_test proxy_smoke_test IsaacInputInjector IsaacInputLauncher IsaacInputPatcher IsaacInputUnpatcher
  )
endif()
