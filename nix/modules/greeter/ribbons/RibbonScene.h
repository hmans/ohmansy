#pragma once
#include <QQuickFramebufferObject>
#include <QtQml/qqmlregistration.h>
#include <cmath>
#include <QVector2D>
#include <QVector3D>

class RibbonScene : public QQuickFramebufferObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QVector2D lightDirection READ lightDirection WRITE setLightDirection NOTIFY lightingChanged)
    Q_PROPERTY(float lightStrength READ lightStrength WRITE setLightStrength NOTIFY lightingChanged)
    Q_PROPERTY(QVector3D lightHighlight READ lightHighlight WRITE setLightHighlight NOTIFY lightingChanged)
    Q_PROPERTY(QVector3D lightShadow READ lightShadow WRITE setLightShadow NOTIFY lightingChanged)
    Q_PROPERTY(float elapsed READ elapsed WRITE setElapsed NOTIFY elapsedChanged)
    Q_PROPERTY(float lightMix READ lightMix WRITE setLightMix NOTIFY lightMixChanged)
    Q_PROPERTY(float renderScale READ renderScale WRITE setRenderScale NOTIFY renderScaleChanged)
    Q_PROPERTY(QSize renderSize READ renderSize NOTIFY renderSizeChanged)
    Q_PROPERTY(int particleLayers READ particleLayers WRITE setParticleLayers NOTIFY particleLayersChanged)
    Q_PROPERTY(float particleMotionDetail READ particleMotionDetail WRITE setParticleMotionDetail NOTIFY particleMotionDetailChanged)
    Q_PROPERTY(bool failed READ failed NOTIFY failedChanged)
    Q_PROPERTY(int framesPerSecond READ framesPerSecond NOTIFY statisticsChanged)
    Q_PROPERTY(double frameTime READ frameTime NOTIFY statisticsChanged)
public:
    QVector2D lightDirection() const { return m_lightDirection; }
    float lightStrength() const { return m_lightStrength; }
    QVector3D lightHighlight() const { return m_lightHighlight; }
    QVector3D lightShadow() const { return m_lightShadow; }
    void setLightDirection(QVector2D value) {
        if (!std::isfinite(value.x()) || !std::isfinite(value.y())) return;
        if (value.lengthSquared() > 1) value.normalize();
        if (value == m_lightDirection) return;
        m_lightDirection = value; emit lightingChanged(); update();
    }
    void setLightStrength(float value) {
        if (!std::isfinite(value)) return;
        value = qBound(0.f, value, 3.f);
        if (value == m_lightStrength) return;
        m_lightStrength = value; emit lightingChanged(); update();
    }
    void setLightHighlight(QVector3D value) {
        if (value == m_lightHighlight) return;
        m_lightHighlight = value; emit lightingChanged(); update();
    }
    void setLightShadow(QVector3D value) {
        if (value == m_lightShadow) return;
        m_lightShadow = value; emit lightingChanged(); update();
    }
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
    int particleLayers() const { return m_particleLayers; }
    void setParticleLayers(int value) {
        value = qBound(0, value, 3);
        if (value == m_particleLayers) return;
        m_particleLayers = value;
        emit particleLayersChanged();
        update();
    }
    float particleMotionDetail() const { return m_particleMotionDetail; }
    void setParticleMotionDetail(float value) {
        if (!std::isfinite(value)) return;
        value = qBound(0.0f, value, 1.0f);
        if (value == m_particleMotionDetail) return;
        m_particleMotionDetail = value;
        emit particleMotionDetailChanged();
        update();
    }
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
    void lightingChanged();
    void elapsedChanged();
    void lightMixChanged();
    void renderScaleChanged();
    void renderSizeChanged();
    void particleLayersChanged();
    void particleMotionDetailChanged();
    void failedChanged();
    void statisticsChanged();
private:
    QVector2D m_lightDirection = QVector2D(-0.70710678f, -0.70710678f);
    float m_lightStrength = 1;
    QVector3D m_lightHighlight = QVector3D(1, 1, 1);
    QVector3D m_lightShadow;
    float m_elapsed = 12;
    float m_lightMix = 0;
    float m_renderScale = 1;
    QSize m_renderSize;
    int m_particleLayers = 3;
    float m_particleMotionDetail = 1;
    bool m_failed = false;
    int m_fps = 0;
    double m_frameTime = 0;
};
