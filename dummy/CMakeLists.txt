# dummy

list(APPEND sources
    "dummy_DropDown.cpp"
    "dummy_DropDown.h"
    "dummy_MainComponent.cpp"
    "dummy_MainComponent.h"
    )

#source_group("" FILES ${sources})

add_library(dummy ${sources})

target_include_directories(dummy PUBLIC .)

# This depends on (header only) boost
target_link_libraries(dummy PRIVATE
  Qt5::Widgets 
  Qt5::Core 
  Qt5::Gui
  Qt5::Svg
)

# All users of this library will need at least C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

