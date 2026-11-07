cmake_minimum_required(VERSION 3.16)
project(interactor_voice C CXX)

# The shared guest recipe: contract-guest-runtime's sandbox API, rv64gc without V and a double-precision
# Variant, configured with repository-riscv64-sysroot's toolchain.cmake. The default root is the goal
# manifest's layout, weft/2-contract/guest-runtime beside weft/3-interactor/voice.
if(NOT DEFINED GUEST_RUNTIME_ROOT)
	get_filename_component(GUEST_RUNTIME_ROOT "${CMAKE_SOURCE_DIR}/../../2-contract/guest-runtime" ABSOLUTE)
endif()
if(NOT EXISTS "${GUEST_RUNTIME_ROOT}/cmake/guest_runtime.cmake")
	message(FATAL_ERROR "no contract-guest-runtime checkout at GUEST_RUNTIME_ROOT=${GUEST_RUNTIME_ROOT}")
endif()
include(${GUEST_RUNTIME_ROOT}/cmake/guest_runtime.cmake)

file(STRINGS vendor/opus/sources.txt OPUS_SOURCES)
list(TRANSFORM OPUS_SOURCES PREPEND vendor/opus/)
add_library(opus STATIC ${OPUS_SOURCES})
target_compile_definitions(opus PRIVATE HAVE_CONFIG_H)
target_compile_options(opus PRIVATE -w)
target_include_directories(opus PRIVATE vendor/opus vendor/opus/celt vendor/opus/silk vendor/opus/silk/float)
target_include_directories(opus PUBLIC vendor/opus/opus)

add_library(voice_codec STATIC src/voice_codec.cpp)
target_include_directories(voice_codec PUBLIC src)
target_link_libraries(voice_codec PUBLIC opus)

add_sandbox_program(voice guest/main.cpp)
target_link_libraries(voice PRIVATE voice_codec -lm -lstdc++)
add_custom_command(TARGET voice POST_BUILD
	COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:voice> ${CMAKE_SOURCE_DIR}/project/voice.elf
	COMMENT "Installing voice.elf into project/"
)
