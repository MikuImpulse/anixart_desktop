cmake_minimum_required(VERSION 3.16)
project(anixart_desktop VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    QuickControls2
    Network
    Svg
)

find_package(PkgConfig REQUIRED)
pkg_check_modules(QRENCODE REQUIRED IMPORTED_TARGET libqrencode)
pkg_check_modules(GST REQUIRED IMPORTED_TARGET
    gstreamer-1.0
    gstreamer-app-1.0
    gstreamer-video-1.0
    gstreamer-audio-1.0
)

set(SOURCES
    src/cpp/main.cpp
    src/cpp/AnixApi.h
    src/cpp/AnixApi.cpp
    src/cpp/AuthManager.h
    src/cpp/AuthManager.cpp
    src/cpp/StreamResolver.h
    src/cpp/StreamResolver.cpp
    src/cpp/VideoPlayer.h
    src/cpp/VideoPlayer.cpp
    src/cpp/CircleImage.h
    src/cpp/CircleImage.cpp
    resources.qrc
)

if(WIN32)
    enable_language(RC)
    list(APPEND SOURCES assets/anixart_app.rc)
endif()

add_executable(Anixart WIN32 ${SOURCES})

target_link_libraries(Anixart PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Network
    Qt6::Svg
    PkgConfig::GST
    PkgConfig::QRENCODE
)

if(WIN32)
    target_link_libraries(Anixart PRIVATE iphlpapi)
endif()

include(GNUInstallDirs)
install(TARGETS Anixart RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    install(FILES anixart.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
    install(FILES assets/anixart_app.png DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/512x512/apps RENAME anixart-desktop.png)

    set(CPACK_PACKAGE_NAME "anixart-desktop")
    set(CPACK_PACKAGE_VENDOR "Anixart Desktop")
    set(CPACK_PACKAGE_CONTACT "Anixart Desktop <anixart-desktop@localhost>")
    set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Native Anixart client")
    set(CPACK_PACKAGING_INSTALL_PREFIX "/usr")

    set(CPACK_DEBIAN_FILE_NAME DEB-DEFAULT)
    set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
    set(CPACK_DEBIAN_PACKAGE_SECTION "video")
    set(CPACK_DEBIAN_PACKAGE_DEPENDS "qml6-module-qtcore, qml6-module-qtqml-models, qml6-module-qtqml-workerscript, qml6-module-qtquick, qml6-module-qtquick-window, qml6-module-qtquick-controls, qml6-module-qtquick-dialogs, qml6-module-qtquick-layouts, qml6-module-qtquick-templates, qt6-qpa-plugins, qt6-wayland, qt6-svg-plugins, qt6-image-formats-plugins, ca-certificates, glib-networking, gstreamer1.0-plugins-base, gstreamer1.0-plugins-good, gstreamer1.0-plugins-bad, gstreamer1.0-libav")

    set(CPACK_RPM_FILE_NAME RPM-DEFAULT)
    set(CPACK_RPM_PACKAGE_RELEASE 1)
    set(CPACK_RPM_PACKAGE_REQUIRES "qt6-qtdeclarative, qt6-qtwayland, ca-certificates, glib-networking, gstreamer1-plugins-base, gstreamer1-plugins-good, gstreamer1-plugins-bad-free, gstreamer1-plugin-libav")
    include(CPack)
endif()
