#include "flutter_window.h"

#include <algorithm>
#include <cstddef>
#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr UINT kMenuNewProject = 41001;
constexpr UINT kMenuOpenProject = 41002;
constexpr UINT kMenuSaveProject = 41003;
constexpr UINT kMenuSaveProjectAs = 41004;
constexpr UINT kMenuUndo = 41101;
constexpr UINT kMenuRedo = 41102;
constexpr UINT kMenuDeleteSelected = 41103;
constexpr UINT kMenuRecentProjectBase = 42000;
constexpr size_t kMaxRecentProjects = 12;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size =
      MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (size <= 0) {
    return std::wstring(value.begin(), value.end());
  }
  std::wstring result(size - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, result.data(), size);
  return result;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  menu_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "nodeql/menu",
          &flutter::StandardMethodCodec::GetInstance());
  menu_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setRecentProjects") {
          HandleSetRecentProjects(call, std::move(result));
          return;
        }
        result->NotImplemented();
      });
  InstallMenuBar();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  menu_channel_ = nullptr;

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_COMMAND: {
      const auto command = LOWORD(wparam);
      switch (command) {
        case kMenuNewProject:
          InvokeMenuMethod("newProject");
          return 0;
        case kMenuOpenProject:
          InvokeMenuMethod("openProject");
          return 0;
        case kMenuSaveProject:
          InvokeMenuMethod("saveProject");
          return 0;
        case kMenuSaveProjectAs:
          InvokeMenuMethod("saveProjectAs");
          return 0;
        case kMenuUndo:
          InvokeMenuMethod("undo");
          return 0;
        case kMenuRedo:
          InvokeMenuMethod("redo");
          return 0;
        case kMenuDeleteSelected:
          InvokeMenuMethod("deleteSelected");
          return 0;
        default:
          if (command >= kMenuRecentProjectBase &&
              command < kMenuRecentProjectBase + kMaxRecentProjects) {
            InvokeRecentProject(command - kMenuRecentProjectBase);
            return 0;
          }
          break;
      }
      break;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::InstallMenuBar() {
  menu_bar_ = CreateMenu();
  projects_menu_ = CreatePopupMenu();
  recent_projects_menu_ = CreatePopupMenu();
  edit_menu_ = CreatePopupMenu();

  AppendMenuW(projects_menu_, MF_STRING, kMenuNewProject,
              L"New Project\tCtrl+Shift+N");
  AppendMenuW(projects_menu_, MF_STRING, kMenuOpenProject,
              L"Open Project...\tCtrl+Shift+O");
  AppendMenuW(projects_menu_, MF_STRING, kMenuSaveProject,
              L"Save Project\tCtrl+S");
  AppendMenuW(projects_menu_, MF_STRING, kMenuSaveProjectAs,
              L"Save Project As...\tCtrl+Shift+S");
  AppendMenuW(projects_menu_, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(projects_menu_, MF_POPUP,
              reinterpret_cast<UINT_PTR>(recent_projects_menu_),
              L"Recent Projects");

  AppendMenuW(edit_menu_, MF_STRING, kMenuUndo, L"Undo\tCtrl+Z");
  AppendMenuW(edit_menu_, MF_STRING, kMenuRedo, L"Redo\tCtrl+Y");
  AppendMenuW(edit_menu_, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(edit_menu_, MF_STRING, kMenuDeleteSelected, L"Delete\tDel");

  AppendMenuW(menu_bar_, MF_POPUP, reinterpret_cast<UINT_PTR>(projects_menu_),
              L"Projects");
  AppendMenuW(menu_bar_, MF_POPUP, reinterpret_cast<UINT_PTR>(edit_menu_),
              L"Edit");

  SetMenu(GetHandle(), menu_bar_);
  RebuildRecentProjectsMenu();
  DrawMenuBar(GetHandle());
}

void FlutterWindow::RebuildRecentProjectsMenu() {
  if (!recent_projects_menu_) {
    return;
  }
  while (GetMenuItemCount(recent_projects_menu_) > 0) {
    DeleteMenu(recent_projects_menu_, 0, MF_BYPOSITION);
  }

  if (recent_projects_.empty()) {
    AppendMenuW(recent_projects_menu_, MF_STRING | MF_GRAYED, 0,
                L"No recent projects");
    return;
  }

  const auto count = std::min(
      recent_projects_.size(), static_cast<size_t>(kMaxRecentProjects));
  for (size_t index = 0; index < count; index++) {
    const auto title = Utf8ToWide(recent_projects_[index].name);
    AppendMenuW(recent_projects_menu_, MF_STRING,
                kMenuRecentProjectBase + static_cast<UINT>(index),
                title.c_str());
  }
  DrawMenuBar(GetHandle());
}

void FlutterWindow::InvokeMenuMethod(const std::string& method) {
  if (!menu_channel_) {
    return;
  }
  menu_channel_->InvokeMethod(method, nullptr);
}

void FlutterWindow::InvokeRecentProject(size_t index) {
  if (!menu_channel_ || index >= recent_projects_.size()) {
    return;
  }
  flutter::EncodableMap args;
  args[flutter::EncodableValue("id")] =
      flutter::EncodableValue(recent_projects_[index].id);
  menu_channel_->InvokeMethod(
      "recentProject", std::make_unique<flutter::EncodableValue>(args));
}

void FlutterWindow::HandleSetRecentProjects(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  recent_projects_.clear();
  const auto* args_value = call.arguments();
  const auto* args =
      args_value ? std::get_if<flutter::EncodableMap>(args_value) : nullptr;
  if (!args) {
    result->Success(flutter::EncodableValue(false));
    RebuildRecentProjectsMenu();
    return;
  }

  const auto items_it = args->find(flutter::EncodableValue("items"));
  if (items_it == args->end()) {
    result->Success(flutter::EncodableValue(false));
    RebuildRecentProjectsMenu();
    return;
  }

  const auto* items = std::get_if<flutter::EncodableList>(&items_it->second);
  if (!items) {
    result->Success(flutter::EncodableValue(false));
    RebuildRecentProjectsMenu();
    return;
  }

  for (const auto& raw_item : *items) {
    const auto* item = std::get_if<flutter::EncodableMap>(&raw_item);
    if (!item) {
      continue;
    }
    const auto id_it = item->find(flutter::EncodableValue("id"));
    const auto name_it = item->find(flutter::EncodableValue("name"));
    if (id_it == item->end() || name_it == item->end()) {
      continue;
    }
    const auto* id = std::get_if<std::string>(&id_it->second);
    const auto* name = std::get_if<std::string>(&name_it->second);
    if (!id || !name) {
      continue;
    }
    recent_projects_.push_back(RecentProject{*id, *name});
  }

  RebuildRecentProjectsMenu();
  result->Success(flutter::EncodableValue(true));
}
