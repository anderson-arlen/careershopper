#include "../../linux/runner/desktop_tray.h"
#include <libayatana-appindicator/app-indicator.h>
#include <libdbusmenu-gtk/parser.h>

struct Fixture {
  GtkApplication* application;
  GtkWindow* window;
};

static void drain_events() {
  while (g_main_context_iteration(nullptr, FALSE)) {}
}

static void setup(Fixture* fixture, gconstpointer) {
  fixture->application = gtk_application_new(
      "com.example.careershopper.TrayTest", G_APPLICATION_NON_UNIQUE);
  g_assert_true(g_application_register(G_APPLICATION(fixture->application), nullptr, nullptr));
  fixture->window = GTK_WINDOW(gtk_application_window_new(fixture->application));
  g_object_ref(fixture->window);
  desktop_tray_attach(fixture->window, "application-x-executable");
  gtk_widget_show(GTK_WIDGET(fixture->window));
  drain_events();
}

static void teardown(Fixture* fixture, gconstpointer) {
  gtk_widget_destroy(GTK_WIDGET(fixture->window));
  g_object_unref(fixture->window);
  g_object_unref(fixture->application);
  drain_events();
}

static void set_connected(Fixture* fixture, gboolean connected) {
  GObject* indicator = G_OBJECT(g_object_get_data(
      G_OBJECT(fixture->window), "careershopper-tray"));
  g_signal_emit_by_name(indicator, "connection-changed", connected);
}

static void act(Fixture* fixture, const char* name) {
  g_action_group_activate_action(G_ACTION_GROUP(fixture->application), name, nullptr);
  drain_events();
}

static void close_to_tray(Fixture* fixture, gconstpointer) {
  set_connected(fixture, TRUE);
  gtk_window_close(fixture->window);
  drain_events();
  g_assert_false(gtk_widget_get_visible(GTK_WIDGET(fixture->window)));
  g_assert_nonnull(gtk_application_get_windows(fixture->application));
  // Hiding does not destroy the window or stop the event loop driving timers.
  gboolean ticked = FALSE;
  g_idle_add([](gpointer data) -> gboolean {
    *static_cast<gboolean*>(data) = TRUE;
    return G_SOURCE_REMOVE;
  }, &ticked);
  drain_events();
  g_assert_true(ticked);
  act(fixture, "show");
  g_assert_true(gtk_widget_get_visible(GTK_WIDGET(fixture->window)));
}

static void host_loss_restores_window(Fixture* fixture, gconstpointer) {
  set_connected(fixture, TRUE);
  act(fixture, "hide");
  g_assert_false(gtk_widget_get_visible(GTK_WIDGET(fixture->window)));
  set_connected(fixture, FALSE);
  g_assert_true(gtk_widget_get_visible(GTK_WIDGET(fixture->window)));
  act(fixture, "hide");
  g_assert_true(gtk_widget_get_visible(GTK_WIDGET(fixture->window)));
}

static void no_host_closes_normally(Fixture* fixture, gconstpointer) {
  set_connected(fixture, FALSE);
  gtk_window_close(fixture->window);
  drain_events();
  g_assert_null(gtk_application_get_windows(fixture->application));
}

static void menu_exports_plain_commands(Fixture* fixture, gconstpointer) {
  AppIndicator* indicator = APP_INDICATOR(g_object_get_data(
      G_OBJECT(fixture->window), "careershopper-tray"));
  GtkWidget* menu = GTK_WIDGET(app_indicator_get_menu(indicator));
  DbusmenuMenuitem* root = dbusmenu_gtk_parse_menu_structure(menu);
  GList* items = dbusmenu_menuitem_get_children(root);
  g_assert_cmpuint(g_list_length(items), ==, 3);
  for (GList* item = items; item != nullptr; item = item->next) {
    const gchar* toggle = dbusmenu_menuitem_property_get(
        DBUSMENU_MENUITEM(item->data), DBUSMENU_MENUITEM_PROP_TOGGLE_TYPE);
    g_assert_true(toggle == nullptr || *toggle == '\0');
  }
  g_object_unref(root);

  // Menu activation still invokes the shared window actions.
  GList* children = gtk_container_get_children(GTK_CONTAINER(menu));
  set_connected(fixture, TRUE);
  gtk_menu_item_activate(GTK_MENU_ITEM(g_list_nth_data(children, 1)));
  g_assert_false(gtk_widget_get_visible(GTK_WIDGET(fixture->window)));
  gtk_menu_item_activate(GTK_MENU_ITEM(children->data));
  g_assert_true(gtk_widget_get_visible(GTK_WIDGET(fixture->window)));
  g_list_free(children);
}

static void quit_exits_run_loop() {
  g_autoptr(GtkApplication) app = gtk_application_new(
      "com.example.careershopper.TrayQuitTest", G_APPLICATION_NON_UNIQUE);
  gboolean shutdown = FALSE;
  g_signal_connect(app, "shutdown", G_CALLBACK(+[](GApplication*, gpointer data) {
    *static_cast<gboolean*>(data) = TRUE;
  }), &shutdown);
  g_signal_connect(app, "activate", G_CALLBACK(+[](GApplication* app, gpointer) {
    GtkWindow* window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(app)));
    desktop_tray_attach(window, "application-x-executable");
    g_action_group_activate_action(G_ACTION_GROUP(app), "quit", nullptr);
    gtk_widget_destroy(GTK_WIDGET(window));
  }), nullptr);
  g_assert_cmpint(g_application_run(G_APPLICATION(app), 0, nullptr), ==, 0);
  g_assert_true(shutdown);
}

// GtkApplication registration is process-wide; isolate each lifecycle case.
static void run_isolated(void (*test)(Fixture*, gconstpointer)) {
  if (!g_test_subprocess()) {
    g_test_trap_subprocess(nullptr, 10 * G_USEC_PER_SEC, G_TEST_SUBPROCESS_DEFAULT);
    g_test_trap_assert_passed();
    return;
  }
  gtk_init(nullptr, nullptr);
  Fixture fixture;
  setup(&fixture, nullptr);
  test(&fixture, nullptr);
  teardown(&fixture, nullptr);
}

int main(int argc, char** argv) {
  g_setenv("GIO_USE_VFS", "local", TRUE);
  g_setenv("NO_AT_BRIDGE", "1", TRUE);
  g_test_init(&argc, &argv, nullptr);
  // Broadway lacks cursor themes; GTK warns when showing a headless window.
  g_log_set_always_fatal(static_cast<GLogLevelFlags>(G_LOG_LEVEL_ERROR | G_LOG_LEVEL_CRITICAL));
  g_test_add_func("/tray/close-show", +[] { run_isolated(close_to_tray); });
  g_test_add_func("/tray/host-loss", +[] { run_isolated(host_loss_restores_window); });
  g_test_add_func("/tray/no-host", +[] { run_isolated(no_host_closes_normally); });
  g_test_add_func("/tray/plain-commands", +[] { run_isolated(menu_exports_plain_commands); });
  g_test_add_func("/tray/quit", +[] {
    if (!g_test_subprocess()) {
      g_test_trap_subprocess(nullptr, 10 * G_USEC_PER_SEC, G_TEST_SUBPROCESS_DEFAULT);
      g_test_trap_assert_passed();
      return;
    }
    gtk_init(nullptr, nullptr);
    quit_exits_run_loop();
  });
  return g_test_run();
}
