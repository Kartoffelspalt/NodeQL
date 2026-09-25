#include "my_application.h"

#include <cstddef>
#include <flutter_linux/flutter_linux.h>
#include <gdk/gdkkeysyms.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* menu_channel;
  GtkWidget* recent_projects_menu;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void invoke_menu_item(GtkWidget* item, MyApplication* self) {
  if (self->menu_channel == nullptr) return;
  const gchar* method = static_cast<const gchar*>(
      g_object_get_data(G_OBJECT(item), "nodeql-method"));
  fl_method_channel_invoke_method(self->menu_channel, method, nullptr, nullptr,
                                  nullptr, nullptr);
}

static void invoke_recent_project(GtkWidget* item, MyApplication* self) {
  if (self->menu_channel == nullptr) return;
  const gchar* id = static_cast<const gchar*>(
      g_object_get_data(G_OBJECT(item), "nodeql-project-id"));
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "id", fl_value_new_string(id));
  fl_method_channel_invoke_method(self->menu_channel, "recentProject", args,
                                  nullptr, nullptr, nullptr);
}

static GtkWidget* add_menu_item(MyApplication* self, GtkWidget* menu,
                                const gchar* label, const gchar* method,
                                GtkAccelGroup* accelerators, guint key,
                                GdkModifierType modifiers) {
  GtkWidget* item = gtk_menu_item_new_with_mnemonic(label);
  g_object_set_data_full(G_OBJECT(item), "nodeql-method", g_strdup(method),
                         g_free);
  g_signal_connect(item, "activate", G_CALLBACK(invoke_menu_item), self);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
  if (key != 0) {
    gtk_widget_add_accelerator(item, "activate", accelerators, key, modifiers,
                               GTK_ACCEL_VISIBLE);
  }
  return item;
}

static void rebuild_recent_projects(MyApplication* self, FlValue* items) {
  GList* children =
      gtk_container_get_children(GTK_CONTAINER(self->recent_projects_menu));
  for (GList* child = children; child != nullptr; child = child->next) {
    gtk_widget_destroy(GTK_WIDGET(child->data));
  }
  g_list_free(children);

  std::size_t count =
      items != nullptr && fl_value_get_type(items) == FL_VALUE_TYPE_LIST
          ? MIN(fl_value_get_length(items), static_cast<std::size_t>(12))
          : 0;
  std::size_t added = 0;
  for (std::size_t index = 0; index < count; ++index) {
    FlValue* project = fl_value_get_list_value(items, index);
    if (fl_value_get_type(project) != FL_VALUE_TYPE_MAP) continue;
    FlValue* id = fl_value_lookup_string(project, "id");
    FlValue* name = fl_value_lookup_string(project, "name");
    if (id == nullptr || name == nullptr ||
        fl_value_get_type(id) != FL_VALUE_TYPE_STRING ||
        fl_value_get_type(name) != FL_VALUE_TYPE_STRING) {
      continue;
    }
    GtkWidget* item = gtk_menu_item_new_with_label(fl_value_get_string(name));
    g_object_set_data_full(G_OBJECT(item), "nodeql-project-id",
                           g_strdup(fl_value_get_string(id)), g_free);
    g_signal_connect(item, "activate", G_CALLBACK(invoke_recent_project),
                     self);
    gtk_menu_shell_append(GTK_MENU_SHELL(self->recent_projects_menu), item);
    ++added;
  }
  if (added == 0) {
    GtkWidget* empty = gtk_menu_item_new_with_label("No recent projects");
    gtk_widget_set_sensitive(empty, FALSE);
    gtk_menu_shell_append(GTK_MENU_SHELL(self->recent_projects_menu), empty);
  }
  gtk_widget_show_all(self->recent_projects_menu);
}

static void menu_method_call_cb(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (g_strcmp0(fl_method_call_get_name(method_call), "setRecentProjects") !=
      0) {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(method_call);
  FlValue* items =
      args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
          ? fl_value_lookup_string(args, "items")
          : nullptr;
  rebuild_recent_projects(self, items);
  g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
  fl_method_call_respond_success(method_call, result, nullptr);
}

static GtkWidget* create_menu_bar(MyApplication* self, GtkWindow* window) {
  GtkWidget* menu_bar = gtk_menu_bar_new();
  GtkWidget* projects = gtk_menu_new();
  GtkWidget* edit = gtk_menu_new();
  GtkAccelGroup* accelerators = gtk_accel_group_new();
  gtk_window_add_accel_group(window, accelerators);

  GtkWidget* projects_root = gtk_menu_item_new_with_mnemonic("_Projects");
  gtk_menu_item_set_submenu(GTK_MENU_ITEM(projects_root), projects);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu_bar), projects_root);
  add_menu_item(self, projects, "_New Project", "newProject", accelerators,
                GDK_KEY_n,
                static_cast<GdkModifierType>(GDK_CONTROL_MASK | GDK_SHIFT_MASK));
  add_menu_item(self, projects, "_Open Project…", "openProject", accelerators,
                GDK_KEY_o,
                static_cast<GdkModifierType>(GDK_CONTROL_MASK | GDK_SHIFT_MASK));
  add_menu_item(self, projects, "_Save Project", "saveProject", accelerators,
                GDK_KEY_s, GDK_CONTROL_MASK);
  add_menu_item(self, projects, "Save Project _As…", "saveProjectAs",
                accelerators, GDK_KEY_s,
                static_cast<GdkModifierType>(GDK_CONTROL_MASK | GDK_SHIFT_MASK));
  gtk_menu_shell_append(GTK_MENU_SHELL(projects), gtk_separator_menu_item_new());
  GtkWidget* recent_root = gtk_menu_item_new_with_label("Recent Projects");
  self->recent_projects_menu = gtk_menu_new();
  gtk_menu_item_set_submenu(GTK_MENU_ITEM(recent_root),
                            self->recent_projects_menu);
  gtk_menu_shell_append(GTK_MENU_SHELL(projects), recent_root);
  rebuild_recent_projects(self, nullptr);

  GtkWidget* edit_root = gtk_menu_item_new_with_mnemonic("_Edit");
  gtk_menu_item_set_submenu(GTK_MENU_ITEM(edit_root), edit);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu_bar), edit_root);
  // Flutter handles Ctrl+Z/Y in the workspace; native accelerators here would
  // steal those keys from text fields where they edit text instead.
  add_menu_item(self, edit, "_Undo", "undo", accelerators, 0,
                static_cast<GdkModifierType>(0));
  add_menu_item(self, edit, "_Redo", "redo", accelerators, 0,
                static_cast<GdkModifierType>(0));
  gtk_menu_shell_append(GTK_MENU_SHELL(edit), gtk_separator_menu_item_new());
  add_menu_item(self, edit, "_Delete selected", "deleteSelected",
                accelerators, 0, static_cast<GdkModifierType>(0));
  g_object_unref(accelerators);
  gtk_widget_show_all(menu_bar);
  return menu_bar;
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "NodeQL");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "NodeQL");
  }

  gtk_window_set_default_size(window, 1280, 720);
  gtk_window_maximize(window);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  GtkWidget* column = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_box_pack_start(GTK_BOX(column), create_menu_bar(self, window), FALSE,
                     FALSE, 0);
  gtk_box_pack_start(GTK_BOX(column), GTK_WIDGET(view), TRUE, TRUE, 0);
  gtk_widget_show(column);
  gtk_container_add(GTK_CONTAINER(window), column);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->menu_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "nodeql/menu",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->menu_channel,
                                            menu_method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_object(&self->menu_channel);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
