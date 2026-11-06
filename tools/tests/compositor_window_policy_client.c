#include <gtk/gtk.h>
#include <glib/gstdio.h>

static GtkApplication *app;
static GtkWindow *parent, *dialog;
static const char *command_path;
static char *previous;

static void clicked(GtkButton *button, gpointer data) {
    (void)button; (void)data;
    char *path = g_strconcat(command_path, ".click", NULL);
    g_file_set_contents(path, "clicked", -1, NULL);
    g_free(path);
}
static gboolean key(GtkEventControllerKey *controller, guint value, guint code,
                    GdkModifierType modifiers, gpointer data) {
    (void)controller; (void)code; (void)modifiers; (void)data;
    if (value == GDK_KEY_a) {
        char *path = g_strconcat(command_path, ".key", NULL);
        g_file_set_contents(path, "a", -1, NULL);
        g_free(path);
    }
    return FALSE;
}
static gboolean poll_command(gpointer data) {
    (void)data;
    char *command = NULL;
    if (!g_file_get_contents(command_path, &command, NULL, NULL)) return TRUE;
    if (g_strcmp0(previous, command) == 0) { g_free(command); return TRUE; }
    g_free(previous); previous = command;
    if (g_str_has_prefix(command, "dialog")) {
        dialog = GTK_WINDOW(gtk_application_window_new(app));
        gtk_window_set_title(dialog, "Shine policy dialog");
        gtk_window_set_transient_for(dialog, parent);
        gtk_window_set_modal(dialog, TRUE);
        gtk_window_set_default_size(dialog, 420, 240);
        gtk_window_set_resizable(dialog, FALSE);
        GtkWidget *button = gtk_button_new_with_label("Dialog input");
        g_signal_connect(button, "clicked", G_CALLBACK(clicked), NULL);
        gtk_window_set_child(dialog, button);
        GtkEventController *controller = gtk_event_controller_key_new();
        g_signal_connect(controller, "key-pressed", G_CALLBACK(key), NULL);
        gtk_widget_add_controller(GTK_WIDGET(dialog), controller);
        gtk_window_present(dialog);
    } else if (g_str_has_prefix(command, "close") && dialog) {
        gtk_window_destroy(dialog); dialog = NULL;
    } else if (g_str_has_prefix(command, "hide")) {
        gtk_widget_set_visible(GTK_WIDGET(parent), FALSE);
    } else if (g_str_has_prefix(command, "show")) {
        gtk_window_present(parent);
    }
    return TRUE;
}
static void activate(GtkApplication *application, gpointer data) {
    (void)data;
    parent = GTK_WINDOW(gtk_application_window_new(application));
    gtk_window_set_title(parent, "Shine policy parent");
    gtk_window_set_child(parent, gtk_label_new("Parent window"));
    gtk_window_present(parent);
    g_timeout_add(50, poll_command, NULL);
}
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    command_path = argv[1];
    app = gtk_application_new("org.ohmansy.WindowPolicyProbe", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int result = g_application_run(G_APPLICATION(app), 1, argv);
    g_object_unref(app); g_free(previous);
    return result;
}
