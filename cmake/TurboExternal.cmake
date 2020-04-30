################################################################################
cmake_minimum_required(VERSION 3.11)

set(NTOP_EXTERNAL "${CMAKE_CURRENT_LIST_DIR}/../external")
set_property(GLOBAL PROPERTY __NTOP_EXTERNAL "${NTOP_EXTERNAL}")

set(NTOP_CACHE_DIR ".cache_${CMAKE_GENERATOR}")
string(REGEX REPLACE "[^A-Za-z0-9_.]" "_" NTOP_CACHE_DIR ${NTOP_CACHE_DIR})
string(TOLOWER ${NTOP_CACHE_DIR} NTOP_CACHE_DIR)

# Prefer git urls by default on non-Windows platforms
if(WIN32)
    option(NTOP_USE_GIT_URLS "Prefer git urls for private projects." OFF)
else()
    option(NTOP_USE_GIT_URLS "Prefer git urls for private projects." ON)
endif()

# Option to skip update checking by CMake
option(NTOP_SKIP_FETCHCONTENT "Skip update check for external projects." OFF)

# Make output of FetchContent verbose
option(NTOP_VERBOSE_FETCHCONTENT "Make output of CMake FetchContent verbose." OFF)

function(ntop_declare name)
    # Convert git urls into https on Windows
    if(NOT NTOP_USE_GIT_URLS)
        cmake_parse_arguments(PARSE_ARGV 1 NTOP_DECL "" "GIT_REPOSITORY" "")
        if(NTOP_DECL_GIT_REPOSITORY)
            string(REPLACE "git@github.com:" "https://github.com/" TMP ${NTOP_DECL_GIT_REPOSITORY})
            set(ARGN GIT_REPOSITORY ${TMP} ${NTOP_DECL_UNPARSED_ARGUMENTS})
        endif()
    endif()

    # Declare content to fetch
    include(FetchContent)
    FetchContent_Declare(
        ${name}
        SOURCE_DIR   ${NTOP_EXTERNAL}/${name}
        DOWNLOAD_DIR ${NTOP_EXTERNAL}/${NTOP_CACHE_DIR}/${name}
        SUBBUILD_DIR ${NTOP_EXTERNAL}/${NTOP_CACHE_DIR}/build/${name}
        TLS_VERIFY OFF
        GIT_CONFIG advice.detachedHead=false
        GIT_PROGRESS ${NTOP_VERBOSE_FETCHCONTENT}
        ${ARGN}
    )
endfunction()

################################################################################
# Generic populate behavior
################################################################################

function(ntop_populate contentName)
    set(OLD_FETCHCONTENT_FULLY_DISCONNECTED ${FETCHCONTENT_FULLY_DISCONNECTED})
    if(NTOP_VERBOSE_FETCHCONTENT)
        set(FETCHCONTENT_QUIET OFF CACHE BOOL "" FORCE)
    else()
        set(FETCHCONTENT_QUIET ON CACHE BOOL "" FORCE)
    endif()

    string(TOLOWER ${contentName} contentNameLower)
    string(TOUPPER ${contentName} contentNameUpper)

    if(NTOP_SKIP_FETCHCONTENT)
        message(STATUS "Skipping update step for package: ${contentName}")
        set(OLD_FETCHCONTENT_FULLY_DISCONNECTED ${FETCHCONTENT_FULLY_DISCONNECTED})
        set(NTOP_SKIP_FETCHCONTENT ON CACHE BOOL "" FORCE)

        # For some reason, when called with FETCHCONTENT_FULLY_DISCONNECTED,
        # FetchContent_Populate assumes that ${contentName}_SOURCE_DIR is set
        # to the default path. So we override it by setting the cache variable
        # FETCHCONTENT_SOURCE_DIR_${contentNameUpper} to the default path that
        # we (ntop) have set previously... unless explicitly set by the user
        # (which is why we do not FORCE it).
        get_property(NTOP_EXTERNAL GLOBAL PROPERTY __NTOP_EXTERNAL)
        set(FETCHCONTENT_SOURCE_DIR_${contentNameUpper} "${NTOP_EXTERNAL}/${name}" CACHE PATH
            "When not empty, overrides where to find pre-populated content for ${contentName}")
        FetchContent_Populate(${contentName})

        set(FETCHCONTENT_FULLY_DISCONNECTED ${OLD_FETCHCONTENT_FULLY_DISCONNECTED} CACHE BOOL "" FORCE)
    else()
        message(STATUS "Checking updates for package: ${contentName}")
        FetchContent_Populate(${contentName})
    endif()
    set(FETCHCONTENT_QUIET ${OLD_FETCHCONTENT_QUIET} CACHE BOOL "" FORCE)

    # Pass variables back to the caller. The variables passed back here
    # must match what FetchContent_GetProperties() sets when it is called
    # with just the content name.
    set(${contentNameLower}_SOURCE_DIR "${${contentNameLower}_SOURCE_DIR}" PARENT_SCOPE)
    set(${contentNameLower}_BINARY_DIR "${${contentNameLower}_BINARY_DIR}" PARENT_SCOPE)
    set(${contentNameLower}_POPULATED  True PARENT_SCOPE)
endfunction()

################################################################################
# Generic fetch behavior
################################################################################

# Default fetch function (fetch only)
function(ntop_fetch)
    include(FetchContent)
    foreach(name IN ITEMS ${ARGN})
        FetchContent_GetProperties(${name})
        if(NOT ${name}_POPULATED)
            ntop_populate(${name})
        endif()
    endforeach()
endfunction()

################################################################################
# Generic import behavior
################################################################################

# Default import function (fetch + add_subdirectory)
function(ntop_import_default name)
    include(FetchContent)
    FetchContent_GetProperties(${name})
    if(NOT ${name}_POPULATED)
        ntop_populate(${name})
        add_subdirectory(${${name}_SOURCE_DIR} ${${name}_BINARY_DIR})
    endif()
endfunction()

# Use some meta-programming to call ntop_import_foo if such a function is user-defined,
# otherwise, we defer to the default behavior which is to call ntop_import_default(foo)
set_property(GLOBAL PROPERTY __TURBO_CMAKE_DIR "${CMAKE_CURRENT_LIST_DIR}")
function(ntop_import)
    get_property(TURBO_CMAKE_DIR GLOBAL PROPERTY __TURBO_CMAKE_DIR)
    foreach(NAME IN ITEMS ${ARGN})
        set(__import_file "${CMAKE_BINARY_DIR}/ntop_import_${NAME}.cmake")
        configure_file("${TURBO_CMAKE_DIR}/TurboImport.cmake.in" "${__import_file}" @ONLY)
        include("${__import_file}")
    endforeach()
endfunction()

################################################################################
# Customized import functions
################################################################################

function(ntop_import_spdlog)
    ntop_import(fmt)
    option(SPDLOG_FMT_EXTERNAL "" ON)
    option(SPDLOG_WCHAR_FILENAMES "" ON)
    ntop_import_default(spdlog)
endfunction()

function(ntop_import_json)
    option(JSON_BuildTests "" OFF)
    option(JSON_MultipleHeaders "" ON)
    ntop_import_default(json)
endfunction()

function(ntop_import_pcg)
    if(NOT TARGET pcg::cpp)
        # Download pcg
        ntop_fetch(pcg)
        FetchContent_GetProperties(pcg)

        # Create interface target
        add_library(pcg_cpp INTERFACE)
        add_library(pcg::cpp ALIAS pcg_cpp)
        target_include_directories(pcg_cpp INTERFACE ${pcg_SOURCE_DIR}/include)
    endif()
endfunction()

function(ntop_import_openvdb)
    if(NOT TARGET openvdb::openvdb)
        # Download openvdb
        ntop_fetch(openvdb)
        FetchContent_GetProperties(openvdb)

        # Create openvdb target
        set(OPENVDB_ROOT ${openvdb_SOURCE_DIR})
        include(openvdb)
    endif()
endfunction()

function(ntop_import_openexr)
    if(NOT TARGET openexr::half)
        # Download openexr
        ntop_fetch(openexr)
        FetchContent_GetProperties(openexr)

        # Create openexr::half target
        set(OPENEXR_ROOT ${openexr_SOURCE_DIR})
        include(openexr)
    endif()
endfunction()

function(ntop_import_tbb)
    if(NOT TARGET tbb::tbb)
        # Download tbb
        ntop_fetch(tbb)
        FetchContent_GetProperties(tbb)

        # Create tbb:tbb target
        set(TBB_BUILD_STATIC ON CACHE BOOL " " FORCE)
        set(TBB_BUILD_SHARED OFF CACHE BOOL " " FORCE)
        set(TBB_BUILD_TBBMALLOC OFF CACHE BOOL " " FORCE)
        set(TBB_BUILD_TBBMALLOC_PROXY OFF CACHE BOOL " " FORCE)
        set(TBB_BUILD_TESTS OFF CACHE BOOL " " FORCE)
        set(TBB_NO_DATE ON CACHE BOOL " " FORCE)

        add_subdirectory(${tbb_SOURCE_DIR} ${tbb_BINARY_DIR})
        set_target_properties(tbb_static PROPERTIES
            INTERFACE_INCLUDE_DIRECTORIES "${tbb_SOURCE_DIR}/include"
        )
        if(NOT MSVC)
            set_target_properties(tbb_static PROPERTIES
                COMPILE_FLAGS "-Wno-implicit-fallthrough -Wno-missing-field-initializers -Wno-unused-parameter -Wno-keyword-macro"
            )
            set_target_properties(tbb_static PROPERTIES POSITION_INDEPENDENT_CODE ON)
        endif()
        add_library(tbb::tbb ALIAS tbb_static)
    endif()
endfunction()

function(ntop_import_nanoflann)
    if(NOT TARGET nanoflann::nanoflann)
        # Download nanoflann
        ntop_fetch(nanoflann)
        FetchContent_GetProperties(nanoflann)

        # Create interface target
        add_library(nanoflann INTERFACE)
        add_library(nanoflann::nanoflann ALIAS nanoflann)
        target_include_directories(nanoflann INTERFACE ${nanoflann_SOURCE_DIR}/include)
    endif()
endfunction()

function(ntop_import_libfive)
    if(NOT TARGET libfive::libfive)
        ntop_import(ntopboost eigen)
        set(LIBFIVE_UNNORMALIZED_DERIVS ON CACHE BOOL " " FORCE)
        set(LIBFIVE_BUILD_STATIC_LIB ON CACHE BOOL " " FORCE)
        set(BUILD_STUDIO_APP OFF CACHE BOOL " " FORCE)
        set(BUILD_GUILE_BINDINGS OFF CACHE BOOL " " FORCE)
        set(LIBFIVE_GENERATE_GIT_VERSION OFF CACHE BOOL " " FORCE)
        ntop_import_default(libfive)
    endif()
endfunction()

function(ntop_import_windingnumber)
    if(NOT TARGET windingnumber::windingnumber)
        # Download windingnumber
        ntop_fetch(windingnumber)
        FetchContent_GetProperties(windingnumber)

        # Create windingnumber target
        set(WINDINGNUMBER_ROOT ${windingnumber_SOURCE_DIR})
        include(windingnumber)
    endif()
endfunction()

function(ntop_import_eigen)
    if(NOT TARGET Eigen3::Eigen)
        ntop_import(mkl)

        # Download Eigen
        ntop_fetch(eigen)
        FetchContent_GetProperties(eigen)

        # Create Eigen target
        set(EIGEN_ROOT ${eigen_SOURCE_DIR})
        include(eigen)
    endif()
endfunction()

function(ntop_import_libigl)
    ntop_import(eigen)
    if(NOT TARGET igl::core)
        set(LIBIGL_BUILD_TESTS            OFF CACHE BOOL "Build libigl unit test"       FORCE)
        set(LIBIGL_BUILD_TUTORIALS        OFF CACHE BOOL "Build libigl tutorial"        FORCE)
        set(LIBIGL_BUILD_PYTHON           OFF CACHE BOOL "Build libigl python bindings" FORCE)
        set(LIBIGL_EXPORT_TARGETS         OFF CACHE BOOL "Export libigl CMake targets"  FORCE)
        set(LIBIGL_USE_STATIC_LIBRARY     ON  CACHE BOOL "Use libigl as static library" FORCE)
        set(LIBIGL_WITH_COMISO            OFF CACHE BOOL "Use CoMiso"                   FORCE)
        set(LIBIGL_WITH_EMBREE            OFF CACHE BOOL "Use Embree"                   FORCE)
        set(LIBIGL_WITH_OPENGL            OFF CACHE BOOL "Use OpenGL"                   FORCE)
        set(LIBIGL_WITH_OPENGL_GLFW       OFF CACHE BOOL "Use GLFW"                     FORCE)
        set(LIBIGL_WITH_OPENGL_GLFW_IMGUI OFF CACHE BOOL "Use ImGui"                    FORCE)
        set(LIBIGL_WITH_PNG               OFF CACHE BOOL "Use PNG"                      FORCE)
        set(LIBIGL_WITH_TETGEN            OFF CACHE BOOL "Use Tetgen"                   FORCE)
        set(LIBIGL_WITH_TRIANGLE          OFF CACHE BOOL "Use Triangle"                 FORCE)
        set(LIBIGL_WITH_PREDICATES        OFF CACHE BOOL "Use exact predicates"         FORCE)
        set(LIBIGL_WITH_XML               OFF CACHE BOOL "Use XML"                      FORCE)
        set(LIBIGL_WITH_PYTHON            OFF CACHE BOOL "Use Python"                   FORCE)

        # Download libigl
        ntop_fetch(libigl)
        FetchContent_GetProperties(libigl)

        # Import libigl targets
        list(APPEND CMAKE_MODULE_PATH "${libigl_SOURCE_DIR}/cmake")

        include(libigl)
    endif()
endfunction()

function(ntop_import_tetwild)
    ntop_import(spdlog libigl geogram)
    ntop_import_default(tetwild)
endfunction()

function(ntop_import_ftetwild)
    ntop_import(spdlog libigl geogram tbb)
    ntop_import_default(ftetwild)
endfunction()

function(ntop_import_geogram)
    ntop_import(tbb)
    ntop_import_default(geogram)
endfunction()

function(ntop_import_stripes)
    ntop_import(eigen mkl suitesparse)
    ntop_import_default(stripes)
endfunction()

function(ntop_import_cppoptlib)
    if(NOT TARGET cppoptlib::cppoptlib)
        # Download CppNumericalSolvers
        ntop_fetch(cppoptlib)
        FetchContent_GetProperties(cppoptlib)

        # Create cppoptlib target
        add_library(cppoptlib INTERFACE)
        add_library(cppoptlib::cppoptlib ALIAS cppoptlib)
        target_include_directories(cppoptlib SYSTEM INTERFACE ${cppoptlib_SOURCE_DIR}/include)
    endif()
endfunction()

function(ntop_import_mkl)
    get_property(TURBO_CMAKE_DIR GLOBAL PROPERTY __TURBO_CMAKE_DIR)
    if(WIN32 AND NOT TARGET mkl::mkl)
        set(ENV{MKLROOT} "${TURBO_CMAKE_DIR}/../libs/mkl")
        set(MKL_SHARED_LIBS OFF)
        set(MKL_USE_ILP64 OFF)
        find_package(MKL REQUIRED)
    endif()
endfunction()

function(ntop_import_suitesparse)
    get_property(TURBO_CMAKE_DIR GLOBAL PROPERTY __TURBO_CMAKE_DIR)
    if(WIN32 AND NOT TARGET SuiteSparse::cholmod)
        set(SuiteSparse_DIR "${TURBO_CMAKE_DIR}/../libs/suitesparse/lib/cmake/suitesparse-5.4.0")
        find_package(SuiteSparse CONFIG REQUIRED)
        set_target_properties(SuiteSparse::amd PROPERTIES IMPORTED_GLOBAL TRUE)
        set_target_properties(SuiteSparse::camd PROPERTIES IMPORTED_GLOBAL TRUE)
        set_target_properties(SuiteSparse::ccolamd PROPERTIES IMPORTED_GLOBAL TRUE)
        set_target_properties(SuiteSparse::cholmod PROPERTIES IMPORTED_GLOBAL TRUE)
        set_target_properties(SuiteSparse::colamd PROPERTIES IMPORTED_GLOBAL TRUE)
        set_target_properties(SuiteSparse::suitesparseconfig PROPERTIES IMPORTED_GLOBAL TRUE)
    endif()
endfunction()

function(ntop_import_gmp)
    get_property(TURBO_CMAKE_DIR GLOBAL PROPERTY __TURBO_CMAKE_DIR)
    if(NOT TARGET gmp::gmp)
        if(WIN32)
            # Somehow providing the .dll as IMPORTED_LOCATION leads to linking
            # error LNK1107, despite this being the approach advocated in the doc.
            add_library(gmp::gmp UNKNOWN IMPORTED GLOBAL)
            set_target_properties(gmp::gmp PROPERTIES
                IMPORTED_LINK_INTERFACE_LANGUAGES "CXX"
                IMPORTED_LOCATION "${TURBO_CMAKE_DIR}/../libs/gmp/libgmp-10.lib"
                # IMPORTED_IMPLIB "${TURBO_CMAKE_DIR}/../libs/gmp/libgmp-10.lib"
            )
        endif()
    endif()
endfunction()

function(ntop_import_mpfr)
    get_property(TURBO_CMAKE_DIR GLOBAL PROPERTY __TURBO_CMAKE_DIR)
    if(NOT TARGET mpfr::mpfr)
        if(WIN32)
            # Somehow providing the .dll as IMPORTED_LOCATION leads to linking
            # error LNK1107, despite this being the approach advocated in the doc.
            add_library(mpfr::mpfr UNKNOWN IMPORTED GLOBAL)
            set_target_properties(mpfr::mpfr PROPERTIES
                IMPORTED_LINK_INTERFACE_LANGUAGES "CXX"
                IMPORTED_LOCATION "${TURBO_CMAKE_DIR}/../libs/mpfr/libmpfr-4.lib"
                # IMPORTED_IMPLIB "${TURBO_CMAKE_DIR}/../libs/mpfr/libmpfr-4.lib"
            )
        endif()
    endif()
endfunction()

function(ntop_import_cgal)
    ntop_import(gmp mpfr)
    ntop_import_default(cgal)
endfunction()

function(ntop_import_simple_svg)
    if(NOT TARGET simple_svg::simple_svg)
        # Download simple_svg
        ntop_fetch(simple_svg)
        FetchContent_GetProperties(simple_svg)

        # Create interface target
        add_library(simple_svg INTERFACE)
        add_library(simple_svg::simple_svg ALIAS simple_svg)
        target_include_directories(simple_svg INTERFACE ${simple_svg_SOURCE_DIR})
    endif()
endfunction()

function(ntop_import_lemon)
    if(NOT TARGET lemon::lemon)
        # Download lemon
        ntop_fetch(lemon)
        FetchContent_GetProperties(lemon)

        # Create target
        set(LEMON_ROOT ${lemon_SOURCE_DIR})
        include(lemon)
    endif()
endfunction()

function(ntop_import_vki)
    ntop_import(mkl)
    ntop_import_default(vki)
endfunction()

function(ntop_import_lib3mf)
    set(USE_INCLUDED_ZLIB OFF CACHE BOOL "" FORCE)
    set(USE_INCLUDED_LIBZIP OFF CACHE BOOL "" FORCE)
    set(LIB3MF_TESTS OFF CACHE BOOL "" FORCE)
    ntop_import_default(lib3mf)
    add_library(lib3mf::lib3mf ALIAS lib3mf)
endfunction()

################################################################################
# Declare third-party dependencies here
################################################################################

ntop_declare(catch2
    GIT_REPOSITORY https://github.com/catchorg/Catch2.git
    # v2.10.0
    GIT_TAG 7c9f92bc1c6e82ad5b6af8dff9f97af880fae9c6
)

ntop_declare(fmt
    GIT_REPOSITORY https://github.com/fmtlib/fmt
    # 6.0.0
    GIT_TAG 7512a55aa3ae309587ca89668ef9ec4074a51a1f
)

ntop_declare(spdlog
    GIT_REPOSITORY https://github.com/gabime/spdlog
    # v1.4.2
    GIT_TAG 1549ff12f1aa61ffc4d9a8727c519034724392a0
)

ntop_declare(json
    GIT_REPOSITORY https://github.com/nlohmann/json
    # v3.7.0
    GIT_TAG 53c3eefa2cf790a7130fed3e13a3be35c2f2ace2
)

ntop_declare(pcg
    GIT_REPOSITORY https://github.com/imneme/pcg-cpp.git
    GIT_TAG b65627800ec5dabe29e3df778e584761ca8e454d
)

ntop_declare(openvdb
    GIT_REPOSITORY https://github.com/AcademySoftwareFoundation/openvdb.git
    # v6.0.0
    GIT_TAG 1fbfc703c38d24015289f7c549e0cd24d7d3b2ad
)

ntop_declare(openexr
    GIT_REPOSITORY https://github.com/openexr/openexr
    # v2.3.0
    GIT_TAG 0ac2ea34c8f3134148a5df4052e40f155b76f6fb
)

ntop_declare(tbb
    GIT_REPOSITORY https://github.com/nTopology/tbb.git
    GIT_TAG 41adc7a7fbe4e6d37fe57186bd85dde99fa61e66
)

ntop_declare(nanoflann
    GIT_REPOSITORY https://github.com/jlblancoc/nanoflann
    # v1.3.0
    GIT_TAG fa9e95faeeeeb5a7595f1090726897845b7ac798
)

ntop_declare(eigen
    GIT_REPOSITORY https://github.com/eigenteam/eigen-git-mirror
    # 3.3.7
    GIT_TAG cf794d3b741a6278df169e58461f8529f43bce5d
)

ntop_declare(libfive
    GIT_REPOSITORY https://github.com/ntopology/libfive
    GIT_TAG 0a2ea3ee2ac389390921949dcbd91eb15221ac55
)

ntop_declare(windingnumber
    GIT_REPOSITORY https://github.com/sideeffects/WindingNumber
    GIT_TAG 1e6081e52905575d8e98fb8b7c0921274a18752f
)

ntop_declare(libigl
    GIT_REPOSITORY https://github.com/libigl/libigl.git
    GIT_TAG 8a448d4af463f5444fe10d335384726196e0c57b
)

ntop_declare(tetwild
    GIT_REPOSITORY https://github.com/nTopology/TetWild.git
    GIT_TAG 806f3c45e53e78d329494da95cbd6b9140e68476
)

ntop_declare(ftetwild
    GIT_REPOSITORY https://github.com/nTopology/fTetWild.git
    GIT_TAG c8bd5f93b1cc453ca45ed2d8f01d3515c264627c
)

ntop_declare(geogram
    GIT_REPOSITORY https://github.com/nTopology/geogram.git
    GIT_TAG f40f0ff8fc5ba0171e2734e72f3437a01ee3f9ed
)

ntop_declare(juce_open_mesh
    GIT_REPOSITORY git@github.com:nTopology/juce_open_mesh.git
    GIT_TAG 978ca851ea054d7f4c986c95f9d4933d342fa9bb
)

ntop_declare(glm
    GIT_REPOSITORY git@github.com:nTopology/glm
    GIT_TAG bde361f7579cbf82838f33c1840ebc14daadf346
)

ntop_declare(muparser
    GIT_REPOSITORY git@github.com:nTopology/juce_muparser
    GIT_TAG c74a50801bac7ec7c058dd521263451bffb2c5bd
)

ntop_declare(cgal
    GIT_REPOSITORY git@github.com:nTopology/cgal
    GIT_TAG 13e520add0c2fb2ab99773ac5d960c65394f1efe
)

ntop_declare(cuba
    GIT_REPOSITORY git@github.com:nTopology/cuba
    GIT_TAG a4ad49efadc929bb0f9e6d82a08bc1a92c2c1492
)

ntop_declare(juce5
    GIT_REPOSITORY git@github.com:nTopology/JUCE5
    GIT_TAG f2cce311c07b11f9c3b06a2bfa4e6bd70eab17b6
)

ntop_declare(vki
    GIT_REPOSITORY git@github.com:nTopology/vki
    GIT_TAG ed28292ef0bc2b2a916303cb4b9c73999702441a
)

ntop_declare(stripes
    GIT_REPOSITORY https://github.com/nTopology/stripes.git
    GIT_TAG 6a44c0e6a8407026d03b95182d85d47991eec0d0
)

ntop_declare(ntparasolid
    GIT_REPOSITORY git@github.com:nTopology/ntparasolid
    GIT_TAG 2b0b57db1603cf8acf4f3ac55ab2cfe46147779c
)

ntop_declare(simple_svg
    GIT_REPOSITORY https://github.com/adishavit/simple-svg.git
    GIT_TAG 4b2fbfc0a6f98dc24e36f6269d5f4b7d49647589
)

ntop_declare(ntopboost
    GIT_REPOSITORY git@github.com:nTopology/ntop-boost
    GIT_TAG 3b0726d13c4fabe7ccc74705810593ffeaf09358
)

ntop_declare(testobjects
    GIT_REPOSITORY git@github.com:nTopology/testobjects
    GIT_TAG 5d33cb4b2cfe017705ae8ce2eb147e2b66510e76
)

ntop_declare(cppoptlib
    GIT_REPOSITORY https://github.com/PatWie/CppNumericalSolvers.git
    GIT_TAG        dfd4686ef4cde941702024a70ac2edc73d5ee88c
)

if(NTOP_NTOPDOCS_TAG)
    ntop_declare(ntopdocs
        GIT_REPOSITORY git@github.com:nTopology/ntopdocs
        GIT_TAG ${NTOP_NTOPDOCS_TAG}
    )
else()
    ntop_declare(ntopdocs
        GIT_REPOSITORY git@github.com:nTopology/ntopdocs
        GIT_TAG 9787f7cff5a9b83b3f24ebd7fc08797465b5a88c
    )
endif()

ntop_declare(lemon
    GIT_REPOSITORY https://github.com/nTopology/lemon.git
    GIT_TAG 67538a2ed3453885c61ac06931f9df730eb28c4a
)

ntop_declare(pybind11
    GIT_REPOSITORY https://github.com/pybind/pybind11
    GIT_TAG dc65d661718ed10a9d212f1949813f7a7acf9437
)

ntop_declare(opensubdiv
    GIT_REPOSITORY https://github.com/nTopology/OpenSubdiv
    GIT_TAG 83de1bd0ad355eb501644d6cad46142a18f38a76
)

ntop_declare(lib3mf
    GIT_REPOSITORY https://github.com/nTopology/lib3mf
    GIT_TAG dcf9456b2c86b964ecfb1399acf06754e0112e6f
)
