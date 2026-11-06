/* A real GTK notification client for the private headless activation trial. */
#include <gtk/gtk.h>
#include <glib/gstdio.h>

static GtkWindow *origin;
static const char *command_path;
static GDBusConnection *bus;
static guint32 notification_id;
static char *activation_token;
static gboolean defer_activation;

static void open_origin(void) {
    if (activation_token) gtk_window_set_startup_id(origin, activation_token);
    gtk_window_present(origin);
}

static void notification_signal(GDBusConnection *connection, const char *sender,
        const char *path, const char *interface, const char *signal,
        GVariant *parameters, gpointer data) {
    (void)connection; (void)sender; (void)path; (void)interface; (void)data;
    guint32 id;
    const char *value;
    if (!g_variant_is_of_type(parameters, G_VARIANT_TYPE("(us)"))) return;
    g_variant_get(parameters, "(u&s)", &id, &value);
    if (id != notification_id) return;
    if (g_str_equal(signal, "ActivationToken")) {
        g_free(activation_token);
        activation_token = g_strdup(value);
    } else if (g_str_equal(signal, "ActionInvoked") && g_str_equal(value, "default")) {
        if (!defer_activation) open_origin();
        char *ack = g_strconcat(command_path, ".action", NULL);
        g_file_set_contents(ack, "action", -1, NULL);
        g_free(ack);
    }
}

static gboolean command(gpointer data) {
    (void)data;
    gchar *text = NULL;
    if (!g_file_get_contents(command_path, &text, NULL, NULL)) return G_SOURCE_CONTINUE;
    g_unlink(command_path);
    if (g_str_has_prefix(text, "notify")) {
        defer_activation = g_str_has_prefix(text, "notify-deferred");
        g_clear_pointer(&activation_token, g_free);
        const char *actions[] = {"default", "Open", NULL};
        GVariant *reply = g_dbus_connection_call_sync(bus, "org.freedesktop.Notifications",
            "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "Notify",
            g_variant_new("(susss^asa{sv}i)", "Notification trial", 0u, "",
                "Notification activation trial", "Return to the originating window",
                actions, NULL, 0), G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, 5000, NULL, NULL);
        g_assert_nonnull(reply);
        g_variant_get(reply, "(u)", &notification_id);
        g_variant_unref(reply);
    } else if (g_str_has_prefix(text, "activate")) {
        open_origin();
    } else if (g_str_has_prefix(text, "present")) {
        gtk_window_present(origin);
    }
    g_free(text);
    return G_SOURCE_CONTINUE;
}

static void activate(GtkApplication *app, gpointer data) {
    (void)data;
    bus = g_application_get_dbus_connection(G_APPLICATION(app));
    // Consume the standard notification token directly. GLib 2.88's
    // GNotification backend drops it before invoking application actions.
    g_dbus_connection_signal_subscribe(bus, "org.freedesktop.Notifications",
        "org.freedesktop.Notifications", NULL, "/org/freedesktop/Notifications",
        NULL, G_DBUS_SIGNAL_FLAGS_NONE, notification_signal, NULL, NULL);
    origin = GTK_WINDOW(gtk_application_window_new(app));
    gtk_window_set_title(origin, "Notification origin");
    gtk_window_set_default_size(origin, 500, 300);
    gtk_window_set_child(origin, gtk_label_new("Notification origin"));
    gtk_window_present(origin);
    GtkWindow *sibling = GTK_WINDOW(gtk_application_window_new(app));
    gtk_window_set_title(sibling, "Other window from the same app");
    gtk_window_set_default_size(sibling, 400, 300);
    gtk_window_present(sibling);
    g_timeout_add(50, command, app);
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    command_path = argv[1];
    GtkApplication *app = gtk_application_new("org.ohmansy.NotificationTrial", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int result = g_application_run(G_APPLICATION(app), 1, argv);
    g_object_unref(app);
    return result;
}
