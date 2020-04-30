set_property(GLOBAL PROPERTY __TURBO_CMAKE_DIR "${CMAKE_CURRENT_LIST_DIR}")

function(ntop_add_tests name)
    get_property(TURBO_CMAKE_DIR GLOBAL PROPERTY __TURBO_CMAKE_DIR)

    ntop_import(catch2)
    add_executable(${name}
        "${TURBO_CMAKE_DIR}/tests.cpp"
        ${ARGN}
    )

    source_group("" FILES ${ARGN})

    target_link_libraries(${name} PUBLIC Catch2::Catch2)

    ntop_fetch(testobjects)

    target_compile_definitions(${name} PRIVATE -DNTOP_TESTOBJECTS_DIR=\"${NTOPOLOGY_WORKSPACE_ROOT}/external/testobjects\")
    target_compile_definitions(${name} PRIVATE -DNTOP_ROOT_DIR=\"${NTOPOLOGY_WORKSPACE_ROOT}\")
    target_compile_definitions(${name} PRIVATE -DCATCH_CONFIG_ENABLE_BENCHMARKING)

    # Register tests
    FetchContent_GetProperties(catch2)
    list(APPEND CMAKE_MODULE_PATH ${catch2_SOURCE_DIR}/contrib)
    set(PARSE_CATCH_TESTS_ADD_TO_CONFIGURE_DEPENDS ON)
    include(Catch)

    catch_discover_tests(${name})
endfunction()

# Set target output directory for a specific target
function(ntop_output_directory target)
    set_target_properties(${target} PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${NTOP_OUTPUT_DIRECTORY}")
    set_target_properties(${target} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${NTOP_OUTPUT_DIRECTORY}")
    set_target_properties(${target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${NTOP_OUTPUT_DIRECTORY}")
endfunction()

# https://stackoverflow.com/questions/32183975/how-to-print-all-the-properties-of-a-target-in-cmake
function(ntop_print_target_properties tgt)
    if(NOT TARGET ${tgt})
      message("There is no target named '${tgt}'")
      return()
    endif()

    execute_process(COMMAND cmake --help-property-list OUTPUT_VARIABLE CMAKE_PROPERTY_LIST)

    # Convert command output into a CMake list
    string(REGEX REPLACE ";" "\\\\;" CMAKE_PROPERTY_LIST "${CMAKE_PROPERTY_LIST}")
    string(REGEX REPLACE "\n" ";" CMAKE_PROPERTY_LIST "${CMAKE_PROPERTY_LIST}")

    foreach (prop ${CMAKE_PROPERTY_LIST})
        string(REPLACE "<CONFIG>" "${CMAKE_BUILD_TYPE}" prop ${prop})
        # Fix https://stackoverflow.com/questions/32197663/how-can-i-remove-the-the-location-property-may-not-be-read-from-target-error-i
        if(prop STREQUAL "LOCATION" OR prop MATCHES "^LOCATION_" OR prop MATCHES "_LOCATION$")
            continue()
        endif()
        # message ("Checking ${prop}")
        get_property(propval TARGET ${tgt} PROPERTY ${prop} SET)
        if (propval)
            get_target_property(propval ${tgt} ${prop})
            message ("${tgt} ${prop} = ${propval}")
        endif()
    endforeach(prop)
endfunction()

# Transitively list all link libraries of a target (recursive call)
function(ntop_get_link_libraries_recursive OUTPUT_LIST_RELEASE OUTPUT_LIST_DEBUG TARGET)
    get_target_property(IMPORTED ${TARGET} IMPORTED)
    get_target_property(TYPE ${TARGET} TYPE)
    if(IMPORTED OR (TYPE STREQUAL "INTERFACE_LIBRARY"))
        get_target_property(LIBS ${TARGET} INTERFACE_LINK_LIBRARIES)
    else()
        get_target_property(LIBS ${TARGET} LINK_LIBRARIES)
    endif()
    set(LIB_FILES_RELEASE "")
    set(LIB_FILES_DEBUG "")
    foreach(LIB IN ITEMS ${LIBS})
        if(TARGET "${LIB}")
            if(NOT (LIB IN_LIST VISITED_TARGETS))
                list(APPEND VISITED_TARGETS ${LIB})
                set(VISITED_TARGETS ${VISITED_TARGETS} PARENT_SCOPE)
                get_target_property(IMPORTED ${LIB} IMPORTED)
                get_target_property(TYPE ${TARGET} TYPE)
                # Somehow on Ubuntu Cosmic, Threads::Threads has type `STATIC_LIBRARY`
                # is in fact an `INTERFACE_LIBRARY`, which will cause the
                # `get_target_property(... LOCATION)` to fail...
                if(IMPORTED AND NOT (TYPE STREQUAL "INTERFACE_LIBRARY")
                    AND NOT (LIB STREQUAL "Threads::Threads"))
                    get_target_property(LIB_FILE_RELEASE ${LIB} LOCATION_RELEASE)
                    get_target_property(LIB_FILE_DEBUG ${LIB} LOCATION_DEBUG)
                else()
                    set(LIB_FILE_RELEASE "")
                    set(LIB_FILE_DEBUG "")
                endif()
                ntop_get_link_libraries_recursive(LINK_LIB_FILES_RELEASE LINK_LIB_FILES_DEBUG ${LIB})
                list(APPEND LIB_FILES_RELEASE ${LIB_FILE_RELEASE} ${LINK_LIB_FILES_RELEASE})
                list(APPEND LIB_FILES_DEBUG ${LIB_FILE_DEBUG} ${LINK_LIB_FILES_DEBUG})
            endif()
        endif()
    endforeach()
    set(${OUTPUT_LIST_RELEASE} ${LIB_FILES_RELEASE} PARENT_SCOPE)
    set(${OUTPUT_LIST_DEBUG} ${LIB_FILES_DEBUG} PARENT_SCOPE)
endfunction()

# Transitively list all link libraries of a target
function(ntop_get_link_libraries OUTPUT_LIST_RELEASE OUTPUT_LIST_DEBUG TARGET)
    set(VISITED_TARGETS "")
    set(LIB_FILES_RELEASE "")
    set(LIB_FILES_DEBUG "")
    ntop_get_link_libraries_recursive(LIB_FILES_RELEASE LIB_FILES_DEBUG ${TARGET})
    set(${OUTPUT_LIST_RELEASE} ${LIB_FILES_RELEASE} PARENT_SCOPE)
    set(${OUTPUT_LIST_DEBUG} ${LIB_FILES_DEBUG} PARENT_SCOPE)
endfunction()

# Copy a list of imported targets into the target folder of another library
# The argument to this function is a list of imported targets which needs to be copied
function(ntop_copy_target_dlls target)
    ntop_get_link_libraries(LIB_FILES_RELEASE LIB_FILES_DEBUG ${target})
    function(ntop_copy_for_release KEEP_RELEASE)
        foreach(location IN ITEMS ${ARGN})
            string(REGEX MATCH "^(.*)\\.[^.]*$" dummy ${location})
            set(location "${CMAKE_MATCH_1}.dll")
            if(EXISTS "${location}" AND location MATCHES "^.*\\.dll$")
                message(STATUS "Creating rule to copy dll: ${location}")
                set(cmd ";copy_if_different;${location};$<TARGET_FILE_DIR:${target}>")
                set(cmd "$<IF:$<EQUAL:$<BOOL:${KEEP_RELEASE}>,$<CONFIG:Release>>,${cmd},echo>")
                add_custom_command(TARGET ${target} POST_BUILD
                    COMMAND "${CMAKE_COMMAND};-E;${cmd}" COMMAND_EXPAND_LISTS)
            endif()
        endforeach()
    endfunction()
    ntop_copy_for_release(YES ${LIB_FILES_RELEASE})
    ntop_copy_for_release(NO ${LIB_FILES_DEBUG})
endfunction()

# Copy an explicit list of dlls into a target's folder after the target is built
# The argument to this function is a list of files to copy
function(ntop_copy_dlls target)
    foreach(filename IN ITEMS ${ARGN})
        add_custom_command(TARGET ${target} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${filename}" $<TARGET_FILE_DIR:${target}>)
    endforeach()
    # This is to avoid adding a line after each `ntop_copy_dlls()`
    # In the future we should get rid of `ntop_copy_dlls` and replace it with `ntop_copy_target_dlls`
    ntop_copy_target_dlls(${target})
endfunction()

# Set source group for files in a given target
function(ntop_source_group target)
    # Note: this assumes that files are either relative to the folder where the
    # target was defined, or belong to the build directory.
    get_target_property(_srcs ${target} SOURCES)
    get_target_property(_root ${target} SOURCE_DIR)
    set(_relsrc ${_srcs})
    set(_gensrc ${_srcs})
    list(FILTER _gensrc INCLUDE REGEX "${CMAKE_BINARY_DIR}/*")
    list(FILTER _relsrc EXCLUDE REGEX "${CMAKE_BINARY_DIR}/*")
    source_group(TREE ${_root} FILES ${_relsrc})
    source_group(generated FILES ${_gensrc})
endfunction()

# Copy a directory into a target's folder after the target is built
function(ntop_copy_folder target folder)
    if(IS_DIRECTORY ${folder})
        get_filename_component(basename ${folder} NAME)
        add_custom_command(TARGET ${target} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_directory
            ${folder} "$<TARGET_FILE_DIR:${target}>/${basename}")
    endif()
endfunction()

function(ntop_binary_builder outName basedir files)
    get_property(TURBO_CMAKE_DIR GLOBAL PROPERTY __TURBO_CMAKE_DIR)
    set(ntop_binary_script "${TURBO_CMAKE_DIR}/../scripts/binary.py")
    find_package(Python3 COMPONENTS Interpreter REQUIRED)
    add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${outName}.cpp ${CMAKE_CURRENT_BINARY_DIR}/${outName}.h
                       COMMAND ${Python3_EXECUTABLE} ${ntop_binary_script} -o ${CMAKE_CURRENT_BINARY_DIR}/${outName} -b ${basedir} ${files}
                       WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
                       COMMENT "-----Generating Binary Data------"
                       DEPENDS ${files})
endfunction(ntop_binary_builder)

function(ntop_add_assets_target targetName componentName assetsDir assetFiles)
    ntop_binary_builder(${componentName} ${assetsDir} "${asset_files}")
    source_group("" FILES
        "${CMAKE_CURRENT_BINARY_DIR}/${componentName}.cpp"
        "${CMAKE_CURRENT_BINARY_DIR}/${componentName}.h")
    add_library(${targetName} STATIC
        "${CMAKE_CURRENT_BINARY_DIR}/${componentName}.cpp"
        "${CMAKE_CURRENT_BINARY_DIR}/${componentName}.h")
    target_include_directories(${targetName} PUBLIC ${CMAKE_CURRENT_BINARY_DIR})
    target_compile_features(${targetName} PUBLIC cxx_std_17)
endfunction()
