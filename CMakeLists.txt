cmake_minimum_required(VERSION 3.16)
project(interactor_voice C CXX)

add_compile_options("-ffile-prefix-map=${CMAKE_SOURCE_DIR}/=")

# The guest builds against the vendored godot-sandbox guest API and nothing else.
set(DOWNLOAD_RUNTIME_API OFF CACHE BOOL "" FORCE)
add_subdirectory(vendor/sandbox-api/cmake sandbox_api)

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
