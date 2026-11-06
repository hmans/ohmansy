#include "NotificationSupport.h"
#include "activation.h"
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QPointer>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTextDocument>
#include <QTimer>
#include <QtGui/qguiapplication_platform.h>
#include <cstring>

namespace {
QString statePath() {
    return QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation)
        + "/ohmansy/notifications.json";
}
struct Request : QObject {
    QPointer<QObject> action;
    uint id;
    xdg_activation_token_v1 *token = nullptr;
    ~Request() override { if (token) xdg_activation_token_v1_destroy(token); }
    void finish(const QString &value = {}) {
        if (token) { xdg_activation_token_v1_destroy(token); token = nullptr; }
        if (action) {
            if (!value.isEmpty()) {
                auto signal = QDBusMessage::createSignal("/org/freedesktop/Notifications",
                    "org.freedesktop.Notifications", "ActivationToken");
                signal << id << value;
                QDBusConnection::sessionBus().send(signal);
            }
            QMetaObject::invokeMethod(action, "invoke", Qt::DirectConnection);
            action.clear();
        }
        deleteLater();
    }
};
}

NotificationSupport::NotificationSupport(QObject *parent) : QObject(parent) {
    auto *native = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
    if (!native) return;
    registry = wl_display_get_registry(native->display());
    static const wl_registry_listener listener = {
        [](void *data, wl_registry *registry, uint32_t name, const char *interface, uint32_t) {
            if (std::strcmp(interface, xdg_activation_v1_interface.name) == 0) {
                auto *self = static_cast<NotificationSupport *>(data);
                self->activation = static_cast<xdg_activation_v1 *>(
                    wl_registry_bind(registry, name, &xdg_activation_v1_interface, 1));
            }
        },
        [](void *, wl_registry *, uint32_t) {}
    };
    wl_registry_add_listener(registry, &listener, this);
    wl_display_roundtrip(native->display());
}
NotificationSupport::~NotificationSupport() {
    if (activation) xdg_activation_v1_destroy(activation);
    if (registry) wl_registry_destroy(registry);
}
void NotificationSupport::invoke(QObject *action, uint notificationId) {
    if (!action) return;
    auto *native = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
    if (!activation || !native || !native->lastInputSeat() || !native->lastInputSerial()) {
        QMetaObject::invokeMethod(action, "invoke", Qt::DirectConnection);
        return;
    }
    auto *request = new Request;
    request->setParent(this);
    request->action = action;
    request->id = notificationId;
    request->token = xdg_activation_v1_get_activation_token(activation);
    static const xdg_activation_token_v1_listener listener = {
        [](void *data, xdg_activation_token_v1 *, const char *token) {
            static_cast<Request *>(data)->finish(QString::fromUtf8(token));
        }
    };
    xdg_activation_token_v1_add_listener(request->token, &listener, request);
    xdg_activation_token_v1_set_serial(request->token, native->lastInputSerial(), native->lastInputSeat());
    xdg_activation_token_v1_commit(request->token);
    wl_display_flush(native->display());
    QTimer::singleShot(1000, request, [request] { request->finish(); });
}
QVariantMap NotificationSupport::load() const {
    QFile file(statePath());
    if (!file.open(QIODevice::ReadOnly)) return {};
    return QJsonDocument::fromJson(file.readAll()).toVariant().toMap();
}
bool NotificationSupport::save(const QVariantMap &state) const {
    QDir().mkpath(QFileInfo(statePath()).absolutePath());
    QSaveFile file(statePath());
    if (!file.open(QIODevice::WriteOnly)) return false;
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    const auto bytes = QJsonDocument::fromVariant(state).toJson(QJsonDocument::Compact);
    return file.write(bytes) == bytes.size() && file.commit();
}
QString NotificationSupport::plainText(const QString &text) const {
    QTextDocument document;
    document.setHtml(text);
    return document.toPlainText();
}
