#include "RibbonScene.h"
#include <QGuiApplication>
#include <QImage>
#include <QOpenGLContext>
#include <QOpenGLExtraFunctions>
#include <QQuickWindow>
#include <QSurfaceFormat>
#include <QTimer>

// Exercise the real FBO renderer under both APIs, without a desktop session.
int main(int argc, char **argv) {
    const bool es = argc == 2 && QByteArray(argv[1]) == "es";
    qputenv("QSG_RENDER_LOOP", "basic");
    QSurfaceFormat format;
    format.setRenderableType(es ? QSurfaceFormat::OpenGLES : QSurfaceFormat::OpenGL);
    format.setVersion(3, es ? 0 : 3);
    format.setProfile(es ? QSurfaceFormat::NoProfile : QSurfaceFormat::CoreProfile);
    QSurfaceFormat::setDefaultFormat(format);
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    QGuiApplication app(argc, argv);
    QQuickWindow window;
    window.resize(320, 200);
    auto *scene = new RibbonScene(window.contentItem());
    scene->setSize(QSizeF(320, 200));
    QObject::connect(scene, &RibbonScene::failedChanged, &app, [] {
        qFatal("Ribbon renderer reported failure");
    });
    bool rendered = false;
    QObject::connect(&window, &QQuickWindow::afterRendering, &app, [&] {
        auto *context = QOpenGLContext::currentContext();
        if (!context || context->isOpenGLES() != es)
            qFatal("Did not get the requested graphics API");
        const auto error = context->extraFunctions()->glGetError();
        if (error != GL_NO_ERROR) qFatal("OpenGL error: 0x%x", error);
        rendered = true;
    }, Qt::DirectConnection);
    QImage dark, light;
    int step = 0;
    QTimer capture;
    capture.setInterval(1000);
    QObject::connect(&capture, &QTimer::timeout, &app, [&] {
        const QImage frame = window.grabWindow();
        if (!rendered || frame.isNull()) qFatal("No rendered frame");
        if (frame.pixelColor(5, 5) == frame.pixelColor(160, 100))
            qFatal("Expected a shaded scene, got a flat frame");
        if (step == 0) {
            dark = frame;
            scene->setLightMix(1);
        } else if (step == 1) {
            light = frame;
            if (qGray(light.pixel(5, 5)) <= qGray(dark.pixel(5, 5)) + 60)
                qFatal("Light palette did not brighten the backdrop");
            scene->setElapsed(20);
        } else {
            if (frame == light) qFatal("Animation did not change the frame");
            qInfo() << (es ? "ES" : "Desktop GL")
                    << "ribbons: dark, light, motion, and GL error checks passed";
            app.quit();
        }
        ++step;
    });
    QTimer::singleShot(20000, &app, [] { qFatal("Render check timed out"); });
    window.show();
    capture.start();
    return app.exec();
}
