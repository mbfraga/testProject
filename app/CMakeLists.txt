add_executable(app main.cpp)

target_link_libraries(app PRIVATE
  dummy
  Qt5::Widgets 
  Qt5::Core 
  Qt5::Gui
)


