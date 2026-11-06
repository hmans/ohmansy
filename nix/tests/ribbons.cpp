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
        } else if (step == 2) {
            if (frame == light) qFatal("Animation did not change the frame");
            // Resizing recreates the multisample target and Qt's resolve target.
            window.resize(480, 300);
            scene->setSize(QSizeF(480, 300));
        } else if (step == 3) {
            if (frame.size() != QSize(480, 300)) qFatal("Resize did not produce a frame");
            if (scene->renderSize() != QSize(480, 300)) qFatal("Unexpected default render size");
            light = frame;
            scene->setRenderScale(0.75);
        } else if (step == 4) {
            if (scene->renderSize() != QSize(360, 225)) qFatal("Render scale did not resize the target");
            if (frame.size() != QSize(480, 300)) qFatal("Render scale changed the display size");
            if (frame == light) qFatal("Render scale did not affect rendered pixels");
            scene->setRenderScale(0.5);
        } else if (step == 5) {
            if (scene->renderSize() != QSize(240, 150)) qFatal("Second render scale did not apply");
            scene->setRenderScale(1);
        } else {
            if (scene->renderSize() != QSize(480, 300)) qFatal("Render scale did not restore the target");
            if (frame != light) qFatal("Render scale round trip changed the scene");
            qInfo() << (es ? "ES" : "Desktop GL")
                    << "ribbons: dark, light, motion, resize, live render scale, and GL error checks passed";
            app.quit();
        }
        ++step;
    });
    QTimer::singleShot(20000, &app, [] { qFatal("Render check timed out"); });
    window.show();
    capture.start();
    return app.exec();
}
