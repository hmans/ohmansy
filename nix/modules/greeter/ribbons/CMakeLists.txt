cmake_minimum_required(VERSION 3.21)
project(OhmansyWelcome LANGUAGES CXX)
find_package(Qt6 REQUIRED COMPONENTS Quick OpenGL)
qt_standard_project_setup(REQUIRES 6.8)
qt_add_qml_module(ohmansy-welcome
    URI Ohmansy.Welcome
    VERSION 1.0
    OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/Ohmansy/Welcome"
    SOURCES RibbonScene.h RibbonScene.cpp
    RESOURCES common.glsl background.frag ribbon.vert ribbon.frag
)
target_link_libraries(ohmansy-welcome PRIVATE Qt6::Quick Qt6::OpenGL)
set(qml_destination "lib/qt-6/qml/Ohmansy/Welcome")
install(TARGETS ohmansy-welcome ohmansy-welcomeplugin LIBRARY DESTINATION "${qml_destination}")
install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/Ohmansy/Welcome/qmldir"
    "${CMAKE_CURRENT_BINARY_DIR}/Ohmansy/Welcome/ohmansy-welcome.qmltypes"
    DESTINATION "${qml_destination}")
