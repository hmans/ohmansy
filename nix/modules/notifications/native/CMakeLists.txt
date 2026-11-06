cmake_minimum_required(VERSION 3.21)
project(OhmansyNotificationSupport LANGUAGES C CXX)
find_package(Qt6 REQUIRED COMPONENTS Quick DBus)
find_package(PkgConfig REQUIRED)
pkg_check_modules(WAYLAND REQUIRED IMPORTED_TARGET wayland-client)
pkg_get_variable(PROTOCOLS wayland-protocols pkgdatadir)
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)
set(protocol "${PROTOCOLS}/staging/xdg-activation/xdg-activation-v1.xml")
add_custom_command(OUTPUT activation.h activation.c
    COMMAND ${WAYLAND_SCANNER} client-header ${protocol} activation.h
    COMMAND ${WAYLAND_SCANNER} private-code ${protocol} activation.c
    DEPENDS ${protocol})
qt_standard_project_setup(REQUIRES 6.8)
qt_add_qml_module(notification-support
    URI Ohmansy.NotificationSupport VERSION 1.0
    OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/Ohmansy/NotificationSupport"
    SOURCES NotificationSupport.h NotificationSupport.cpp activation.h activation.c)
target_include_directories(notification-support PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
target_link_libraries(notification-support PRIVATE Qt6::Quick Qt6::DBus PkgConfig::WAYLAND)
set(destination "lib/qt-6/qml/Ohmansy/NotificationSupport")
install(TARGETS notification-support notification-supportplugin LIBRARY DESTINATION "${destination}")
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/Ohmansy/NotificationSupport/qmldir"
    "${CMAKE_CURRENT_BINARY_DIR}/Ohmansy/NotificationSupport/notification-support.qmltypes"
    DESTINATION "${destination}")
