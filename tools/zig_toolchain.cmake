if(CMAKE_GENERATOR MATCHES "Visual Studio")
  message(FATAL_ERROR "Visual Studio generator not supported, use: cmake -G Ninja")
endif()

set(SCRIPT_DIR "${CMAKE_CURRENT_LIST_DIR}")

if(WIN32)
  set(SCRIPT_EXT ".cmd")
else()
  set(SCRIPT_EXT ".sh")
endif()

set(CMAKE_C_COMPILER "${SCRIPT_DIR}/zig-cc${SCRIPT_EXT}")
set(CMAKE_CXX_COMPILER "${SCRIPT_DIR}/zig-c++${SCRIPT_EXT}")
set(CMAKE_C_COMPILER_TARGET ${TARGET})
set(CMAKE_CXX_COMPILER_TARGET ${TARGET})

set(CMAKE_AR "${SCRIPT_DIR}/zig-ar${SCRIPT_EXT}")
set(CMAKE_RANLIB "${SCRIPT_DIR}/zig-ranlib${SCRIPT_EXT}")
set(CMAKE_RC_COMPILER "${SCRIPT_DIR}/zig-rc${SCRIPT_EXT}")
