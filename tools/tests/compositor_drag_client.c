#include <gtk/gtk.h>

static const char *result_path;

static void began(GtkDragSource *source, GdkDrag *drag, gpointer data) {
    (void)source; (void)data;
    gtk_drag_icon_set_child(GTK_DRAG_ICON(gtk_drag_icon_get_for_drag(drag)),
                           gtk_label_new("Drag icon"));
    g_file_set_contents(result_path, "started", -1, NULL);
}

static void ended(GtkDragSource *source, GdkDrag *drag, gboolean deleted, gpointer data) {
    (void)source; (void)drag; (void)deleted; (void)data;
    g_file_set_contents(result_path, "ended", -1, NULL);
}

static void activate(GtkApplication *app, gpointer data) {
    (void)data;
    GtkWidget *window = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(window), "Shine drag probe");
    GtkWidget *area = gtk_label_new("Drag anywhere in this window");
    GtkDragSource *source = gtk_drag_source_new();
    gtk_drag_source_set_actions(source, GDK_ACTION_COPY);
    GdkContentProvider *content = gdk_content_provider_new_typed(G_TYPE_STRING, "drag probe");
    gtk_drag_source_set_content(source, content);
    g_object_unref(content);
    g_signal_connect(source, "drag-begin", G_CALLBACK(began), NULL);
    g_signal_connect(source, "drag-end", G_CALLBACK(ended), NULL);
    gtk_widget_add_controller(area, GTK_EVENT_CONTROLLER(source));
    gtk_window_set_child(GTK_WINDOW(window), area);
    gtk_window_present(GTK_WINDOW(window));
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    result_path = argv[1];
    GtkApplication *app = gtk_application_new("org.ohmansy.DragProbe", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int result = g_application_run(G_APPLICATION(app), 1, argv);
    g_object_unref(app);
    return result;
}
