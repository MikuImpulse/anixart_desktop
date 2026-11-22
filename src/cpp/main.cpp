#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QIcon>
#include <QDir>
#include <gst/gst.h>

#include <QQmlNetworkAccessManagerFactory>
#include <QNetworkDiskCache>
#include <QStandardPaths>

#include "AnixApi.h"
#include "AuthManager.h"
#include "StreamResolver.h"
#include "VideoPlayer.h"
#include "CircleImage.h"

class CustomNetworkAccessManagerFactory : public QQmlNetworkAccessManagerFactory
{
public:
    explicit CustomNetworkAccessManagerFactory(AnixApi &api) : m_api(api) {}

    QNetworkAccessManager *create(QObject *parent) override
    {
        QNetworkAccessManager *manager = new QNetworkAccessManager(parent);
        QNetworkDiskCache *diskCache = new QNetworkDiskCache(manager);
        QString cachePath = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
#ifdef Q_OS_LINUX
        cachePath += "/anixart_linux";
#endif
        cachePath += "/image_cache";
        diskCache->setCacheDirectory(cachePath);
        diskCache->setMaximumCacheSize(256 * 1024 * 1024);
        manager->setCache(diskCache);
        manager->setTransferTimeout(15000);
        QObject::connect(&m_api, &AnixApi::networkRouteChanged, manager, &QNetworkAccessManager::clearConnectionCache);
        return manager;
    }

private:
    AnixApi &m_api;
};

int main(int argc, char *argv[])
{
#ifdef Q_OS_WIN
    if (!qEnvironmentVariableIsSet("QSG_USE_SIMPLE_ANIMATION_DRIVER")) {
        qputenv("QSG_USE_SIMPLE_ANIMATION_DRIVER", "1");
    }
#endif

    QGuiApplication app(argc, argv);
#ifdef Q_OS_WIN
    const QDir runtime(QCoreApplication::applicationDirPath());
    if (runtime.exists("gstreamer-1.0")) {
        g_setenv("GST_PLUGIN_SYSTEM_PATH_1_0", runtime.absoluteFilePath("gstreamer-1.0").toUtf8().constData(), TRUE);
        g_setenv("GIO_MODULE_DIR", runtime.absoluteFilePath("gio").toUtf8().constData(), TRUE);
        g_setenv("SSL_CERT_FILE", runtime.absoluteFilePath("ca-bundle.crt").toUtf8().constData(), TRUE);
        gst_registry_fork_set_enabled(FALSE);
    }
#endif
    gst_init(&argc, &argv);

    app.setApplicationName("Anixart");
    app.setApplicationDisplayName("Anixart");
    app.setOrganizationName("Anixart");
    app.setDesktopFileName("anixart");
    app.setWindowIcon(QIcon(":/assets/anixart_app.png"));
    QQuickStyle::setStyle("Material");

    qmlRegisterType<VideoPlayer>("Anixart", 1, 0, "VideoPlayer");
    qmlRegisterType<StreamResolver>("Anixart", 1, 0, "StreamResolver");
    qmlRegisterType<CircleImage>("Anixart", 1, 0, "CircleImage");

    AnixApi anixApi;
    AuthManager authManager;
    QObject::connect(&app, &QCoreApplication::aboutToQuit, &anixApi, &AnixApi::flushPlaybackProgress);

    QQmlApplicationEngine engine;
    engine.setNetworkAccessManagerFactory(new CustomNetworkAccessManagerFactory(anixApi));
    engine.rootContext()->setContextProperty("anixApi", &anixApi);
    engine.rootContext()->setContextProperty("authManager", &authManager);

    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) return 1;

    return app.exec();
}
