# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# Check if the target architecture and compiler supports some special
# instruction sets that would boost performance.
include(CheckCXXCompilerFlag)
# x86/amd64 compiler flags
check_cxx_compiler_flag("-msse4.2" CXX_SUPPORTS_SSE4_2)
# power compiler flags
check_cxx_compiler_flag("-maltivec" CXX_SUPPORTS_ALTIVEC)
# Arm64 compiler flags
set(ARROW_ARMV8_CRC_FLAG "-march=armv8-a+crc")
check_cxx_compiler_flag(${ARROW_ARMV8_CRC_FLAG} CXX_SUPPORTS_ARMCRC)
set(ARROW_ARMV8_CRC_CRYPTO_FLAG "-march=armv8-a+crc+crypto")
check_cxx_compiler_flag(${ARROW_ARMV8_CRC_CRYPTO_FLAG} CXX_SUPPORTS_ARMV8_CRC_CRYPTO)

# Support C11
set(CMAKE_C_STANDARD 11)

# This ensures that things like gnu++11 get passed correctly
set(CMAKE_CXX_STANDARD 11)

# We require a C++11 compliant compiler
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Build with -fPIC so that can static link our libraries into other people's
# shared libraries
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

string(TOUPPER ${CMAKE_BUILD_TYPE} CMAKE_BUILD_TYPE)

set(UNKNOWN_COMPILER_MESSAGE
    "Unknown compiler: ${CMAKE_CXX_COMPILER_VERSION} ${CMAKE_CXX_COMPILER_VERSION}")

# compiler flags that are common across debug/release builds
if(WIN32)
  # TODO(wesm): Change usages of C runtime functions that MSVC says are
  # insecure, like std::getenv
  add_definitions(-D_CRT_SECURE_NO_WARNINGS)

  if(MSVC)
    if(MSVC_VERSION VERSION_LESS 19)
      message(FATAL_ERROR "Only MSVC 2015 (Version 19.0) and later are supported
      by Arrow. Found version ${CMAKE_CXX_COMPILER_VERSION}.")
    endif()

    # ARROW-1931 See https://github.com/google/googletest/issues/1318
    #
    # This is added to CMAKE_CXX_FLAGS instead of CXX_COMMON_FLAGS since only the
    # former is passed into the external projects
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /D_SILENCE_TR1_NAMESPACE_DEPRECATION_WARNING")

    if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
      # clang-cl
      set(CXX_COMMON_FLAGS "-EHsc")
    else()
      # Fix annoying D9025 warning
      string(REPLACE "/W3" "" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")

      # Set desired warning level (e.g. set /W4 for more warnings)
      #
      # ARROW-2986: Without /EHsc we get C4530 warning
      set(CXX_COMMON_FLAGS "/W3 /EHsc")
    endif()

    if(ARROW_USE_STATIC_CRT)
      foreach(c_flag
              CMAKE_CXX_FLAGS
              CMAKE_CXX_FLAGS_RELEASE
              CMAKE_CXX_FLAGS_DEBUG
              CMAKE_CXX_FLAGS_MINSIZEREL
              CMAKE_CXX_FLAGS_RELWITHDEBINFO
              CMAKE_C_FLAGS
              CMAKE_C_FLAGS_RELEASE
              CMAKE_C_FLAGS_DEBUG
              CMAKE_C_FLAGS_MINSIZEREL
              CMAKE_C_FLAGS_RELWITHDEBINFO)
        string(REPLACE "/MD" "-MT" ${c_flag} "${${c_flag}}")
      endforeach()
    endif()

    # Support large object code
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} /bigobj")
  endif(MSVC)
else()
  # Common flags set below with warning level
  set(CXX_COMMON_FLAGS "")
endif()

# BUILD_WARNING_LEVEL add warning/error compiler flags. The possible values are
# - PRODUCTION: Build with `-Wall` but do not add `-Werror`, so warnings do not
#   halt the build.
# - CHECKIN: Build with `-Wall` and `-Wextra`.  Also, add `-Werror` in debug mode
#   so that any important warnings fail the build.
# - EVERYTHING: Like `CHECKIN`, but possible extra flags depending on the
#               compiler, including `-Wextra`, `-Weverything`, `-pedantic`.
#               This is the most aggressive warning level.

# Defaults BUILD_WARNING_LEVEL to `CHECKIN`, unless CMAKE_BUILD_TYPE is
# `RELEASE`, then it will default to `PRODUCTION`. The goal of defaulting to
# `CHECKIN` is to avoid friction with long response time from CI.
if(NOT BUILD_WARNING_LEVEL)
  if("${CMAKE_BUILD_TYPE}" STREQUAL "RELEASE")
    set(BUILD_WARNING_LEVEL PRODUCTION)
  else()
    set(BUILD_WARNING_LEVEL CHECKIN)
  endif()
endif(NOT BUILD_WARNING_LEVEL)
string(TOUPPER ${BUILD_WARNING_LEVEL} BUILD_WARNING_LEVEL)

message(STATUS "Arrow build warning level: ${BUILD_WARNING_LEVEL}")

macro(arrow_add_werror_if_debug)
  if("${CMAKE_BUILD_TYPE}" STREQUAL "DEBUG")
    # Treat all compiler warnings as errors
    if(MSVC)
      set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} /WX")
    else()
      set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Werror")
    endif()
  endif()
endmacro()

if("${BUILD_WARNING_LEVEL}" STREQUAL "CHECKIN")
  # Pre-checkin builds
  if(MSVC)
    # https://docs.microsoft.com/en-us/cpp/error-messages/compiler-warnings/compiler-warnings-by-compiler-version
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} /W3")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} /wd4365")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} /wd4267")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} /wd4838")
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang"
         OR CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wall")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wextra")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wdocumentation")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-missing-braces")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-unused-parameter")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-unknown-warning-option")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-constant-logical-operand")
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wall")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-conversion")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-sign-conversion")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-unused-variable")
  else()
    message(FATAL_ERROR "${UNKNOWN_COMPILER_MESSAGE}")
  endif()
  arrow_add_werror_if_debug()

elseif("${BUILD_WARNING_LEVEL}" STREQUAL "EVERYTHING")
  # Pedantic builds for fixing warnings
  if(MSVC)
    string(REPLACE "/W3" "" CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS}")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} /Wall")
    # https://docs.microsoft.com/en-us/cpp/build/reference/compiler-option-warning-level
    # /wdnnnn disables a warning where "nnnn" is a warning number
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang"
         OR CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Weverything")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-c++98-compat")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-c++98-compat-pedantic")
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wall")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wpedantic")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wextra")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-unused-parameter")
  else()
    message(FATAL_ERROR "${UNKNOWN_COMPILER_MESSAGE}")
  endif()
  arrow_add_werror_if_debug()

else()
  # Production builds (warning are not treated as errors)
  if(MSVC)
    # https://docs.microsoft.com/en-us/cpp/build/reference/compiler-option-warning-level
    # TODO: Enable /Wall and disable individual warnings until build compiles without errors
    # /wdnnnn disables a warning where "nnnn" is a warning number
    string(REPLACE "/W3" "" CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS}")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} /W3")
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang"
         OR CMAKE_CXX_COMPILER_ID STREQUAL "Clang"
         OR CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wall")
  else()
    message(FATAL_ERROR "${UNKNOWN_COMPILER_MESSAGE}")
  endif()

endif()

if(MSVC)
  # Disable annoying "performance warning" about int-to-bool conversion
  set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} /wd4800")

  # Disable unchecked iterator warnings, equivalent to /D_SCL_SECURE_NO_WARNINGS
  set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} /wd4996")

  # Disable "switch statement contains 'default' but no 'case' labels" warning
  # (required for protobuf, see https://github.com/protocolbuffers/protobuf/issues/6885)
  set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} /wd4065")
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  if(CMAKE_CXX_COMPILER_VERSION VERSION_GREATER "6.0")
    # Without this, gcc >= 7 warns related to changes in C++17
    set(CXX_ONLY_FLAGS "${CXX_ONLY_FLAGS} -Wno-noexcept-type")
  endif()

  if(CMAKE_CXX_COMPILER_VERSION VERSION_GREATER "4.9")
    # Add colors when paired with ninja
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fdiagnostics-color=always")
  endif()

  if(CMAKE_CXX_COMPILER_VERSION VERSION_LESS "6.0")
    # Work around https://gcc.gnu.org/bugzilla/show_bug.cgi?id=43407
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-attributes")
  endif()
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang"
       OR CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
  # Clang options for all builds

  # Using Clang with ccache causes a bunch of spurious warnings that are
  # purportedly fixed in the next version of ccache. See the following for details:
  #
  #   http://petereisentraut.blogspot.com/2011/05/ccache-and-clang.html
  #   http://petereisentraut.blogspot.com/2011/09/ccache-and-clang-part-2.html
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Qunused-arguments")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Qunused-arguments")

  # Avoid clang error when an unknown warning flag is passed
  set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-unknown-warning-option")
  # Add colors when paired with ninja
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fcolor-diagnostics")

  if(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
    # Depending on the default OSX_DEPLOYMENT_TARGET (< 10.9), libstdc++ may be
    # the default standard library which does not support C++11. libc++ is the
    # default from 10.9 onward.
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -stdlib=libc++")
  endif()
endif()

# if build warning flags is set, add to CXX_COMMON_FLAGS
if(BUILD_WARNING_FLAGS)
  # Use BUILD_WARNING_FLAGS with BUILD_WARNING_LEVEL=everything to disable
  # warnings (use with Clang's -Weverything flag to find potential errors)
  set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} ${BUILD_WARNING_FLAGS}")
endif(BUILD_WARNING_FLAGS)

# Only enable additional instruction sets if they are supported
if(CXX_SUPPORTS_SSE4_2 AND ARROW_SSE42)
  set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -msse4.2")
endif()

if(CXX_SUPPORTS_ALTIVEC AND ARROW_ALTIVEC)
  set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -maltivec")
endif()

if(CXX_SUPPORTS_ARMCRC)
  if(CXX_SUPPORTS_ARMV8_CRC_CRYPTO)
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} ${ARROW_ARMV8_CRC_CRYPTO_FLAG}")
  else()
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} ${ARROW_ARMV8_CRC_FLAG}")
  endif()
endif()

if(ARROW_USE_SIMD)
  add_definitions(-DARROW_USE_SIMD)
endif()

# ----------------------------------------------------------------------
# Setup Gold linker, if available. Code originally from Apache Kudu

# Interrogates the linker version via the C++ compiler to determine whether
# we're using the gold linker, and if so, extracts its version.
#
# If the gold linker is being used, sets GOLD_VERSION in the parent scope with
# the extracted version.
#
# Any additional arguments are passed verbatim into the C++ compiler invocation.
function(GET_GOLD_VERSION)
  # The gold linker is only for ELF binaries, which macOS doesn't use.
  execute_process(COMMAND ${CMAKE_CXX_COMPILER} "-Wl,--version" ${ARGN}
                  ERROR_QUIET
                  OUTPUT_VARIABLE LINKER_OUTPUT)
  # We're expecting LINKER_OUTPUT to look like one of these:
  #   GNU gold (version 2.24) 1.11
  #   GNU gold (GNU Binutils for Ubuntu 2.30) 1.15
  if(LINKER_OUTPUT MATCHES "GNU gold")
    string(REGEX MATCH "GNU gold \\([^\\)]*\\) (([0-9]+\\.?)+)" _ "${LINKER_OUTPUT}")
    if(NOT CMAKE_MATCH_1)
      message(SEND_ERROR "Could not extract GNU gold version. "
                         "Linker version output: ${LINKER_OUTPUT}")
    endif()
    set(GOLD_VERSION "${CMAKE_MATCH_1}" PARENT_SCOPE)
  endif()
endfunction()

# Is the compiler hard-wired to use the gold linker?
if(NOT WIN32 AND NOT APPLE)
  get_gold_version()
  if(GOLD_VERSION)
    set(MUST_USE_GOLD 1)
  elseif(ARROW_USE_LD_GOLD)
    # Can the compiler optionally enable the gold linker?
    get_gold_version("-fuse-ld=gold")

    # We can't use the gold linker if it's inside devtoolset because the compiler
    # won't find it when invoked directly from make/ninja (which is typically
    # done outside devtoolset).
    execute_process(COMMAND which ld.gold
                    OUTPUT_VARIABLE GOLD_LOCATION
                    OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    if("${GOLD_LOCATION}" MATCHES "^/opt/rh/devtoolset")
      message("Skipping optional gold linker (version ${GOLD_VERSION}) because "
              "it's in devtoolset")
      set(GOLD_VERSION)
    endif()
  endif()

  if(GOLD_VERSION)
    # Older versions of the gold linker are vulnerable to a bug [1] which
    # prevents weak symbols from being overridden properly. This leads to
    # omitting of dependencies like tcmalloc (used in Kudu, where this
    # workaround was written originally)
    #
    # How we handle this situation depends on other factors:
    # - If gold is optional, we won't use it.
    # - If gold is required, we'll either:
    #   - Raise an error in RELEASE builds (we shouldn't release such a product), or
    #   - Drop tcmalloc in all other builds.
    #
    # 1. https://sourceware.org/bugzilla/show_bug.cgi?id=16979.
    if("${GOLD_VERSION}" VERSION_LESS "1.12")
      set(ARROW_BUGGY_GOLD 1)
    endif()
    if(MUST_USE_GOLD)
      message("Using hard-wired gold linker (version ${GOLD_VERSION})")
      if(ARROW_BUGGY_GOLD)
        if("${ARROW_LINK}" STREQUAL "d" AND "${CMAKE_BUILD_TYPE}" STREQUAL "RELEASE")
          message(SEND_ERROR "Configured to use buggy gold with dynamic linking "
                             "in a RELEASE build")
        endif()
      endif()
    elseif(NOT ARROW_BUGGY_GOLD)
      # The Gold linker must be manually enabled.
      set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fuse-ld=gold")
      set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fuse-ld=gold")
      message("Using optional gold linker (version ${GOLD_VERSION})")
    else()
      message("Optional gold linker is buggy, using ld linker instead")
    endif()
  else()
    message("Using ld linker")
  endif()
endif()

# compiler flags for different build types (run 'cmake -DCMAKE_BUILD_TYPE=<type> .')
# For all builds:
# For CMAKE_BUILD_TYPE=Debug
#   -ggdb: Enable gdb debugging
# For CMAKE_BUILD_TYPE=FastDebug
#   Same as DEBUG, except with some optimizations on.
# For CMAKE_BUILD_TYPE=Release
#   -O3: Enable all compiler optimizations
#   Debug symbols are stripped for reduced binary size. Add
#   -DARROW_CXXFLAGS="-g" to add them
if(NOT MSVC)
  if(ARROW_GGDB_DEBUG)
    set(ARROW_DEBUG_SYMBOL_TYPE "gdb")
    set(C_FLAGS_DEBUG "-g${ARROW_DEBUG_SYMBOL_TYPE} -O0")
    set(C_FLAGS_FASTDEBUG "-g${ARROW_DEBUG_SYMBOL_TYPE} -O1")
    set(CXX_FLAGS_DEBUG "-g${ARROW_DEBUG_SYMBOL_TYPE} -O0")
    set(CXX_FLAGS_FASTDEBUG "-g${ARROW_DEBUG_SYMBOL_TYPE} -O1")
  else()
    set(C_FLAGS_DEBUG "-g -O0")
    set(C_FLAGS_FASTDEBUG "-g -O1")
    set(CXX_FLAGS_DEBUG "-g -O0")
    set(CXX_FLAGS_FASTDEBUG "-g -O1")
  endif()

  set(C_FLAGS_RELEASE "-O3 -DNDEBUG")
  set(CXX_FLAGS_RELEASE "-O3 -DNDEBUG")
endif()

set(C_FLAGS_PROFILE_GEN "${CXX_FLAGS_RELEASE} -fprofile-generate")
set(C_FLAGS_PROFILE_BUILD "${CXX_FLAGS_RELEASE} -fprofile-use")
set(CXX_FLAGS_PROFILE_GEN "${CXX_FLAGS_RELEASE} -fprofile-generate")
set(CXX_FLAGS_PROFILE_BUILD "${CXX_FLAGS_RELEASE} -fprofile-use")

# Set compile flags based on the build type.
message(
  "Configured for ${CMAKE_BUILD_TYPE} build (set with cmake -DCMAKE_BUILD_TYPE={release,debug,...})"
  )
if("${CMAKE_BUILD_TYPE}" STREQUAL "DEBUG")
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${C_FLAGS_DEBUG}")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${CXX_FLAGS_DEBUG}")
elseif("${CMAKE_BUILD_TYPE}" STREQUAL "RELWITHDEBINFO")

elseif("${CMAKE_BUILD_TYPE}" STREQUAL "FASTDEBUG")
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${C_FLAGS_FASTDEBUG}")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${CXX_FLAGS_FASTDEBUG}")
elseif("${CMAKE_BUILD_TYPE}" STREQUAL "RELEASE")
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${C_FLAGS_RELEASE}")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${CXX_FLAGS_RELEASE}")
elseif("${CMAKE_BUILD_TYPE}" STREQUAL "PROFILE_GEN")
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${C_FLAGS_PROFILE_GEN}")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${CXX_FLAGS_PROFILE_GEN}")
elseif("${CMAKE_BUILD_TYPE}" STREQUAL "PROFILE_BUILD")
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${C_FLAGS_PROFILE_BUILD}")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${CXX_FLAGS_PROFILE_BUILD}")
else()
  message(FATAL_ERROR "Unknown build type: ${CMAKE_BUILD_TYPE}")
endif()

if("${CMAKE_CXX_FLAGS}" MATCHES "-DNDEBUG")
  set(ARROW_DEFINITION_FLAGS "-DNDEBUG")
else()
  set(ARROW_DEFINITION_FLAGS "")
endif()

message(STATUS "Build Type: ${CMAKE_BUILD_TYPE}")

# ----------------------------------------------------------------------
# MSVC-specific linker options

if(MSVC)
  set(MSVC_LINKER_FLAGS)
  if(MSVC_LINK_VERBOSE)
    set(MSVC_LINKER_FLAGS "${MSVC_LINKER_FLAGS} /VERBOSE:LIB")
  endif()
  if(NOT ARROW_USE_STATIC_CRT)
    set(MSVC_LINKER_FLAGS "${MSVC_LINKER_FLAGS} /NODEFAULTLIB:LIBCMT")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${MSVC_LINKER_FLAGS}")
    set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} ${MSVC_LINKER_FLAGS}")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${MSVC_LINKER_FLAGS}")
  endif()
endif()
