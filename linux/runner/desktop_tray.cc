#include "desktop_tray.h"

#include <libayatana-appindicator/app-indicator.h>

static void show_window(GSimpleAction*, GVariant*, gpointer data) {
  gtk_window_present(GTK_WINDOW(data));
}

static void hide_window(GSimpleAction*, GVariant*, gpointer data) {
  gtk_widget_hide(GTK_WIDGET(data));
}

static void quit_application(GSimpleAction*, GVariant*, gpointer data) {
  g_application_quit(G_APPLICATION(gtk_window_get_application(GTK_WINDOW(data))));
}

static GAction* hide_action(GtkWindow* window) {
  return g_action_map_lookup_action(
      G_ACTION_MAP(gtk_window_get_application(window)), "hide");
}

static gboolean close_window(GtkWidget* window, GdkEvent*, gpointer) {
  if (!g_action_get_enabled(hide_action(GTK_WINDOW(window)))) return FALSE;
  gtk_widget_hide(window);
  return TRUE;
}

static void tray_connection_changed(AppIndicator*, gboolean connected,
                                    GtkWindow* window) {
  g_simple_action_set_enabled(G_SIMPLE_ACTION(hide_action(window)), connected);
  // Losing the tray must not leave a running app with no reachable window.
  if (!connected && !gtk_widget_get_visible(GTK_WIDGET(window))) {
    gtk_window_present(window);
  }
}

static void destroy_tray(GtkWidget* window, gpointer) {
  AppIndicator* indicator = APP_INDICATOR(
      g_object_steal_data(G_OBJECT(window), "careershopper-tray"));
  g_signal_handlers_disconnect_by_data(indicator, window);
  app_indicator_set_status(indicator, APP_INDICATOR_STATUS_PASSIVE);
  gtk_widget_destroy(GTK_WIDGET(app_indicator_get_menu(indicator)));
  g_object_unref(indicator);
}

void desktop_tray_attach(GtkWindow* window, const gchar* icon_path) {
  GtkApplication* application = gtk_window_get_application(window);
  const GActionEntry actions[] = {
      {"show", show_window, nullptr, nullptr, nullptr, {0, 0, 0}},
      {"hide", hide_window, nullptr, nullptr, nullptr, {0, 0, 0}},
      {"quit", quit_application, nullptr, nullptr, nullptr, {0, 0, 0}},
  };
  g_action_map_add_action_entries(G_ACTION_MAP(application), actions,
                                G_N_ELEMENTS(actions), window);
  g_simple_action_set_enabled(G_SIMPLE_ACTION(hide_action(window)), FALSE);

  // Model-backed GTK items inherit GtkCheckMenuItem, which libdbusmenu
  // exports as checkboxes even for stateless actions.
  GtkWidget* menu = gtk_menu_new();
  gtk_widget_insert_action_group(menu, "app", G_ACTION_GROUP(application));
  const gchar* labels[] = {"Open CareerShopper", "Hide window", "Quit CareerShopper"};
  const gchar* names[] = {"app.show", "app.hide", "app.quit"};
  for (guint i = 0; i < G_N_ELEMENTS(labels); ++i) {
    GtkWidget* item = gtk_menu_item_new_with_label(labels[i]);
    gtk_actionable_set_action_name(GTK_ACTIONABLE(item), names[i]);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
  }
  gtk_widget_show_all(menu);

  AppIndicator* indicator = APP_INDICATOR(g_object_new(
      APP_INDICATOR_TYPE, "id", "careershopper", "category", "ApplicationStatus",
      "icon-name", icon_path, "title", "CareerShopper", nullptr));
  app_indicator_set_menu(indicator, GTK_MENU(menu));
  app_indicator_set_status(indicator, APP_INDICATOR_STATUS_ACTIVE);
  g_object_set_data_full(G_OBJECT(window), "careershopper-tray", indicator,
                        g_object_unref);
  g_signal_connect_object(indicator, "connection-changed",
                          G_CALLBACK(tray_connection_changed), window,
                          static_cast<GConnectFlags>(0));
  g_signal_connect(window, "delete-event", G_CALLBACK(close_window), nullptr);
  g_signal_connect(window, "destroy", G_CALLBACK(destroy_tray), nullptr);
}
