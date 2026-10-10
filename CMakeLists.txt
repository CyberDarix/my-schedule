cmake_minimum_required(VERSION 3.21)

project(DarkShell VERSION 1.0 LANGUAGES CXX)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick)

qt_standard_project_setup(REQUIRES 6.5)

if(WIN32)
    enable_language(RC)
    configure_file(app.rc.in "${CMAKE_CURRENT_BINARY_DIR}/app.rc" @ONLY)
endif()

if(WIN32)
    qt_add_executable(DarkShell WIN32 main.cpp)
    target_sources(DarkShell PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/app.rc")
else()
    qt_add_executable(DarkShell main.cpp)
endif()

if(APPLE)
    set_target_properties(DarkShell PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_BUNDLE_NAME "My Schedule"
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.myschedule.app"
        MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    )
endif()

set_target_properties(DarkShell PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

target_compile_options(DarkShell PRIVATE
    $<$<CXX_COMPILER_ID:MSVC>:/Zc:__cplusplus>
    $<$<CXX_COMPILER_ID:MSVC>:/permissive->
)

qt_add_qml_module(DarkShell
    URI DarkShell
    VERSION 1.0
    QML_FILES
        Main.qml
)

qt_add_resources(DarkShell "application_assets"
    PREFIX "/app"
    FILES
        assets/my_schedule_logo.png
)

target_link_libraries(DarkShell PRIVATE Qt6::Quick)

if(WIN32)
    get_filename_component(QT_INSTALL_ROOT "${Qt6_DIR}/../../.." ABSOLUTE)
    set(QT_RUNTIME_BIN "${QT_INSTALL_ROOT}/bin")
    set(QT_RUNTIME_QML "${QT_INSTALL_ROOT}/qml")
    set(DARKSHELL_QML_IMPORT_DIR "$<TARGET_FILE_DIR:DarkShell>/qml")
    set(DARKSHELL_PLUGIN_DIR "$<TARGET_FILE_DIR:DarkShell>/plugins")

    set(DARKSHELL_RUNTIME_DLLS
        libc++.dll
        libunwind.dll
        Qt6Core.dll
        Qt6Gui.dll
        Qt6LabsFolderListModel.dll
        Qt6Network.dll
        Qt6OpenGL.dll
        Qt6Qml.dll
        Qt6QmlMeta.dll
        Qt6QmlModels.dll
        Qt6QmlWorkerScript.dll
        Qt6Quick.dll
        Qt6QuickControls2.dll
        Qt6QuickControls2Basic.dll
        Qt6QuickControls2BasicStyleImpl.dll
        Qt6QuickControls2Impl.dll
        Qt6QuickDialogs2.dll
        Qt6QuickDialogs2QuickImpl.dll
        Qt6QuickDialogs2Utils.dll
        Qt6QuickLayouts.dll
        Qt6QuickTemplates2.dll
    )

    foreach(runtime_dll IN LISTS DARKSHELL_RUNTIME_DLLS)
        add_custom_command(TARGET DarkShell POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${QT_RUNTIME_BIN}/${runtime_dll}"
                "$<TARGET_FILE_DIR:DarkShell>/${runtime_dll}"
            VERBATIM
        )
    endforeach()

    add_custom_command(TARGET DarkShell POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory
            "${DARKSHELL_PLUGIN_DIR}/platforms"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${QT_INSTALL_ROOT}/plugins/platforms/qwindows.dll"
            "${DARKSHELL_PLUGIN_DIR}/platforms/qwindows.dll"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${QT_RUNTIME_QML}/QtQuick"
            "${DARKSHELL_QML_IMPORT_DIR}/QtQuick"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${QT_RUNTIME_QML}/QtQml"
            "${DARKSHELL_QML_IMPORT_DIR}/QtQml"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${QT_RUNTIME_QML}/QML"
            "${DARKSHELL_QML_IMPORT_DIR}/QML"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${QT_RUNTIME_QML}/Qt"
            "${DARKSHELL_QML_IMPORT_DIR}/Qt"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_SOURCE_DIR}/qt.conf"
            "$<TARGET_FILE_DIR:DarkShell>/qt.conf"
        VERBATIM
    )
elseif(APPLE OR CMAKE_SYSTEM_NAME STREQUAL "Linux")
    include(GNUInstallDirs)
    qt_generate_deploy_qml_app_script(
        TARGET DarkShell
        OUTPUT_SCRIPT DARKSHELL_DEPLOY_SCRIPT
    )

    install(TARGETS DarkShell
        BUNDLE DESTINATION .
        RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
    )
    install(SCRIPT "${DARKSHELL_DEPLOY_SCRIPT}")

    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        configure_file(
            "${CMAKE_CURRENT_SOURCE_DIR}/my-schedule.desktop.in"
            "${CMAKE_CURRENT_BINARY_DIR}/my-schedule.desktop"
            @ONLY
        )
        install(FILES "${CMAKE_CURRENT_BINARY_DIR}/my-schedule.desktop"
            DESTINATION "${CMAKE_INSTALL_DATADIR}/applications"
        )
        install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/assets/my_schedule_logo.png"
            DESTINATION "${CMAKE_INSTALL_DATADIR}/icons/hicolor/512x512/apps"
            RENAME my-schedule.png
        )
    endif()
endif()
