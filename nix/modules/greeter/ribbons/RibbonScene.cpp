#include "RibbonScene.h"
#include <QElapsedTimer>
#include <QFile>
#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QOpenGLExtraFunctions>
#include <QOpenGLShaderProgram>
#include <QPointer>
#include <QQuickOpenGLUtils>
#include <QVector2D>
#include <algorithm>

// OpenGL port of app/native/WelcomeCanvas.m. Keep the same draw order and
// per-ribbon depth prepass; ordinary alpha sorting loses the fabric folds.
class RibbonRenderer : public QQuickFramebufferObject::Renderer,
                       protected QOpenGLExtraFunctions {
public:
    ~RibbonRenderer() override { if (vao) glDeleteVertexArrays(1, &vao); }
    void synchronize(QQuickFramebufferObject *item) override {
        owner = static_cast<RibbonScene *>(item);
        elapsed = owner->elapsed();
        lightMix = owner->lightMix();
    }
    QOpenGLFramebufferObject *createFramebufferObject(const QSize &requested) override {
        const double scale = std::min(1.0, 2400.0 / std::max(1, requested.width()));
        QSize size(std::max(64, int(requested.width() * scale)),
                   std::max(64, int(requested.height() * scale)));
        QOpenGLFramebufferObjectFormat format;
        format.setAttachment(QOpenGLFramebufferObject::CombinedDepthStencil);
        format.setInternalTextureFormat(GL_RGBA8);
        return new QOpenGLFramebufferObject(size, format);
    }
    void render() override {
        if (!attempted) initialize();
        if (!ready) { QQuickOpenGLUtils::resetOpenGLState(); return; }
        const QSize size = framebufferObject()->size();
        glViewport(0, 0, size.width(), size.height());
        glDisable(GL_SCISSOR_TEST);
        glDisable(GL_CULL_FACE);
        glDisable(GL_STENCIL_TEST);
        // ES has no core FRAMEBUFFER_SRGB switch; this target is linear RGBA8.
        if (!openGLES) glDisable(GL_FRAMEBUFFER_SRGB);
        glDisable(GL_POLYGON_OFFSET_FILL);
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        glDepthMask(GL_TRUE);
        glClearDepthf(1.0f);
        glClearColor(0.065f, 0.077f, 0.12f, 1);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
        glBindVertexArray(vao);
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_BLEND);
        background.bind();
        uniforms(background, size);
        glDrawArrays(GL_TRIANGLES, 0, 3);

        ribbons.bind();
        uniforms(ribbons, size);
        glEnable(GL_DEPTH_TEST);
        glDepthFunc(GL_LEQUAL);
        glEnable(GL_BLEND);
        glBlendEquation(GL_FUNC_ADD);
        glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ZERO);
        for (int id = 0; id < 3; ++id) {
            ribbons.setUniformValue("ribbonId", id);
            glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
            glDepthMask(GL_TRUE);
            glEnable(GL_POLYGON_OFFSET_FILL);
            glPolygonOffset(1.0f, 1.0f);
            glDrawArrays(GL_TRIANGLES, 0, 256 * 12 * 6);
            glDisable(GL_POLYGON_OFFSET_FILL);
            glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
            glDepthMask(GL_FALSE);
            glDrawArrays(GL_TRIANGLES, 0, 256 * 12 * 6);
        }
        // The scene is an opaque composited backdrop. Preserve alpha=1 for Qt.
        glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_TRUE);
        glClear(GL_COLOR_BUFFER_BIT);
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        glDepthMask(GL_TRUE);
        glBindVertexArray(0);
        ribbons.release();
        QQuickOpenGLUtils::resetOpenGLState();
        ++frames;
        if (statistics.elapsed() >= 1000) {
            const int fps = qRound(frames * 1000.0 / statistics.elapsed());
            const double ms = statistics.elapsed() / double(frames);
            QMetaObject::invokeMethod(owner, [item = owner, fps, ms] {
                if (item) item->reportStatistics(fps, ms);
            }, Qt::QueuedConnection);
            statistics.restart();
            frames = 0;
        }
    }
private:
    QByteArray source(const char *name) {
        QFile file(QStringLiteral(":/qt/qml/Ohmansy/Welcome/") + name);
        if (!file.open(QIODevice::ReadOnly)) return {};
        return file.readAll();
    }
    void uniforms(QOpenGLShaderProgram &program, QSize size) {
        program.setUniformValue("size", QVector2D(size.width(), size.height()));
        program.setUniformValue("time", elapsed);
        program.setUniformValue("lightMix", lightMix);
    }
    void initialize() {
        attempted = true;
        const auto *context = QOpenGLContext::currentContext();
        if (context) {
            qInfo() << "Ohmansy ribbons context:" << context->format()
                    << "OpenGL ES:" << context->isOpenGLES();
        }
        openGLES = context && context->isOpenGLES();
        const auto minimum = openGLES ? qMakePair(3, 0) : qMakePair(3, 3);
        if (!context || context->format().version() < minimum) {
            qWarning() << "Ohmansy ribbons require OpenGL 3.3 or OpenGL ES 3.0.";
            QMetaObject::invokeMethod(owner, [item = owner] {
                if (item) item->reportFailure();
            }, Qt::QueuedConnection);
            return;
        }
        initializeOpenGLFunctions();
        // Share shader bodies across desktop GL and ES. Explicit high precision
        // also keeps uniforms and stage interfaces compatible when linking ES.
        const QByteArray header = openGLES
            ? "#version 300 es\nprecision highp float;\nprecision highp int;\n"
            : "#version 330 core\n";
        const QByteArray shared = header + source("common.glsl");
        const QByteArray fullscreen = header + "void main() {"
            "vec2 p[3] = vec2[3](vec2(-1,-1),vec2(3,-1),vec2(-1,3));"
            "gl_Position = vec4(p[gl_VertexID],0,1); }";
        ready = background.addShaderFromSourceCode(QOpenGLShader::Vertex, fullscreen)
            && background.addShaderFromSourceCode(QOpenGLShader::Fragment, shared + source("background.frag"))
            && background.link()
            && ribbons.addShaderFromSourceCode(QOpenGLShader::Vertex, shared + source("ribbon.vert"))
            && ribbons.addShaderFromSourceCode(QOpenGLShader::Fragment, shared + source("ribbon.frag"))
            && ribbons.link();
        if (!ready) {
            qWarning() << "Ohmansy ribbons could not initialize:" << background.log() << ribbons.log();
            QMetaObject::invokeMethod(owner, [item = owner] {
                if (item) item->reportFailure();
            }, Qt::QueuedConnection);
            return;
        }
        glGenVertexArrays(1, &vao);
        statistics.start();
        qInfo() << "Ohmansy welcome ribbons:" << reinterpret_cast<const char *>(glGetString(GL_RENDERER));
    }
    QPointer<RibbonScene> owner;
    QOpenGLShaderProgram background, ribbons;
    QElapsedTimer statistics;
    GLuint vao = 0;
    float elapsed = 12;
    float lightMix = 0;
    int frames = 0;
    bool attempted = false, ready = false, openGLES = false;
};

QQuickFramebufferObject::Renderer *RibbonScene::createRenderer() const {
    return new RibbonRenderer;
}
