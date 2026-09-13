#ifndef CAREERSHOPPER_DESKTOP_TRAY_H_
#define CAREERSHOPPER_DESKTOP_TRAY_H_

#include <gtk/gtk.h>

// Window actions are presentation-only; the Flutter engine remains alive.
void desktop_tray_attach(GtkWindow* window, const gchar* icon_path);

#endif
