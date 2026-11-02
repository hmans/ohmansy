#pragma once
#include <QQuickFramebufferObject>
#include <QtQml/qqmlregistration.h>

class RibbonScene : public QQuickFramebufferObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(float elapsed READ elapsed WRITE setElapsed NOTIFY elapsedChanged)
    Q_PROPERTY(bool failed READ failed NOTIFY failedChanged)
    Q_PROPERTY(int framesPerSecond READ framesPerSecond NOTIFY statisticsChanged)
    Q_PROPERTY(double frameTime READ frameTime NOTIFY statisticsChanged)
public:
    explicit RibbonScene(QQuickItem *parent = nullptr) : QQuickFramebufferObject(parent) {
        setMirrorVertically(true);
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
    int framesPerSecond() const { return m_fps; }
    double frameTime() const { return m_frameTime; }
    void reportFailure() { m_failed = true; emit failedChanged(); }
    void reportStatistics(int fps, double frameTime) {
        m_fps = fps; m_frameTime = frameTime; emit statisticsChanged();
    }
signals:
    void elapsedChanged();
    void failedChanged();
    void statisticsChanged();
private:
    float m_elapsed = 12;
    bool m_failed = false;
    int m_fps = 0;
    double m_frameTime = 0;
};
