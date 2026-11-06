#pragma once
#include <QObject>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

struct wl_registry;
struct xdg_activation_v1;

class NotificationSupport : public QObject {
    Q_OBJECT
    QML_ELEMENT
public:
    explicit NotificationSupport(QObject *parent = nullptr);
    ~NotificationSupport() override;
    // Only call in response to user input. The compositor validates the serial.
    Q_INVOKABLE void invoke(QObject *action, uint notificationId);
    Q_INVOKABLE QVariantMap load() const;
    Q_INVOKABLE bool save(const QVariantMap &state) const;
    Q_INVOKABLE QString plainText(const QString &text) const;
private:
    wl_registry *registry = nullptr;
    xdg_activation_v1 *activation = nullptr;
};
