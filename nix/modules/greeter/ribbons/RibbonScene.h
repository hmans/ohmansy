#pragma once
#include <QQuickFramebufferObject>
#include <QtQml/qqmlregistration.h>
#include <cmath>

class RibbonScene : public QQuickFramebufferObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(float elapsed READ elapsed WRITE setElapsed NOTIFY elapsedChanged)
    Q_PROPERTY(float lightMix READ lightMix WRITE setLightMix NOTIFY lightMixChanged)
    Q_PROPERTY(float renderScale READ renderScale WRITE setRenderScale NOTIFY renderScaleChanged)
    Q_PROPERTY(QSize renderSize READ renderSize NOTIFY renderSizeChanged)
    Q_PROPERTY(bool failed READ failed NOTIFY failedChanged)
    Q_PROPERTY(int framesPerSecond READ framesPerSecond NOTIFY statisticsChanged)
    Q_PROPERTY(double frameTime READ frameTime NOTIFY statisticsChanged)
public:
    explicit RibbonScene(QQuickItem *parent = nullptr) : QQuickFramebufferObject(parent) {
        setMirrorVertically(true);
        setSmooth(true);
    }
    Renderer *createRenderer() const override;
    float elapsed() const { return m_elapsed; }
    void setElapsed(float value) {
        if (value == m_elapsed) return;
        m_elapsed = value;
        emit elapsedChanged();
        update();
    }
    bool failed() const { return m_failed; }
    float lightMix() const { return m_lightMix; }
    void setLightMix(float value) {
        value = qBound(0.0f, value, 1.0f);
        if (value == m_lightMix) return;
        m_lightMix = value;
        emit lightMixChanged();
        update();
    }
    int framesPerSecond() const { return m_fps; }
    float renderScale() const { return m_renderScale; }
    void setRenderScale(float value) {
        if (!std::isfinite(value)) return;
        value = qBound(0.25f, value, 1.0f);
        if (value == m_renderScale) return;
        m_renderScale = value;
        emit renderScaleChanged();
        update();
    }
    QSize renderSize() const { return m_renderSize; }
    void reportRenderSize(QSize value) {
        if (value == m_renderSize) return;
        m_renderSize = value;
        emit renderSizeChanged();
    }
    double frameTime() const { return m_frameTime; }
    void reportFailure() { m_failed = true; emit failedChanged(); }
    void reportStatistics(int fps, double frameTime) {
        m_fps = fps; m_frameTime = frameTime; emit statisticsChanged();
    }
signals:
    void elapsedChanged();
    void lightMixChanged();
    void renderScaleChanged();
    void renderSizeChanged();
    void failedChanged();
    void statisticsChanged();
private:
    float m_elapsed = 12;
    float m_lightMix = 0;
    float m_renderScale = 1;
    QSize m_renderSize;
    bool m_failed = false;
    int m_fps = 0;
    double m_frameTime = 0;
};
