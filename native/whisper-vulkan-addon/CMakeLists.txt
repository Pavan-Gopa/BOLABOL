cmake_minimum_required(VERSION 3.19)
project(whisper_vulkan_addon LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Allow user to point to Vulkan SDK; fallback to env VULKAN_SDK
if(NOT DEFINED VULKAN_SDK_ROOT)
  if(DEFINED ENV{VULKAN_SDK})
    set(VULKAN_SDK_ROOT $ENV{VULKAN_SDK})
  endif()
endif()

if(NOT VULKAN_SDK_ROOT)
  message(WARNING "VULKAN_SDK or VULKAN_SDK_ROOT not set. Building stub addon that will force fallback.")
  include_directories(${CMAKE_JS_INC})
  add_library(whisper_vulkan_addon MODULE src/stub.c)
  set_target_properties(whisper_vulkan_addon PROPERTIES PREFIX "" SUFFIX ".node" LINK_FLAGS "-undefined dynamic_lookup")
  return()
endif()

message(STATUS "Using Vulkan SDK at: ${VULKAN_SDK_ROOT}")

set(WHISPER_CPP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/whisper.cpp)
if(NOT EXISTS ${WHISPER_CPP_DIR}/src/whisper.cpp)
  message(FATAL_ERROR "Expected whisper.cpp sources (with src/whisper.cpp) at ${WHISPER_CPP_DIR}. Run npm run prepare:whisper first.")
endif()

# Minimal subset of whisper.cpp sources required
# Enable Vulkan in embedded whisper.cpp build
set(GGML_VULKAN ON CACHE BOOL "Enable Vulkan backend in ggml" FORCE)
set(GGML_METAL OFF CACHE BOOL "Disable Metal to avoid conflicts" FORCE)
add_subdirectory(${WHISPER_CPP_DIR} whispercpp-build EXCLUDE_FROM_ALL)

# Vulkan include/lib paths
include_directories(${VULKAN_SDK_ROOT}/Include ${WHISPER_CPP_DIR})
if(APPLE)
  # Only add existing lib directory (MoltenVK). The extra lib/macOS path is optional in some SDK layouts.
  if(EXISTS "${VULKAN_SDK_ROOT}/lib")
    link_directories(${VULKAN_SDK_ROOT}/lib)
  endif()
  if(EXISTS "${VULKAN_SDK_ROOT}/lib/macOS")
    link_directories(${VULKAN_SDK_ROOT}/lib/macOS)
  endif()
endif()

include_directories(${CMAKE_JS_INC})
add_library(whisper_vulkan_addon MODULE src/addon.cc)

# Ensure proper naming (.node) for Node addon
set_target_properties(whisper_vulkan_addon PROPERTIES
  PREFIX ""
  SUFFIX ".node"
  LINK_FLAGS "-undefined dynamic_lookup"
)

target_include_directories(whisper_vulkan_addon PRIVATE 
  ${WHISPER_CPP_DIR}/src 
  ${WHISPER_CPP_DIR}/include 
  ${WHISPER_CPP_DIR}/examples 
  ${VULKAN_SDK_ROOT}/Include 
  ${CMAKE_JS_INC} 
  ${CMAKE_CURRENT_SOURCE_DIR}/node_modules/node-addon-api)

target_sources(whisper_vulkan_addon PRIVATE src/audio_decode.cpp)

if(APPLE)
  # Link by logical name to avoid baking absolute SDK paths into the binary
  set(VK_LIB vulkan)
else()
  set(VK_LIB vulkan)
endif()

target_link_libraries(whisper_vulkan_addon PRIVATE whisper ${VK_LIB} ${CMAKE_JS_LIB})

# Help runtime find loader-relative libs when copied next to the addon
set_target_properties(whisper_vulkan_addon PROPERTIES
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "@loader_path"
)

target_compile_definitions(whisper_vulkan_addon PRIVATE GGML_USE_VULKAN)

install(TARGETS whisper_vulkan_addon DESTINATION .)
