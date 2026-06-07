#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <vector>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  struct RecentProject {
    std::string id;
    std::string name;
  };

  void InstallMenuBar();
  void RebuildRecentProjectsMenu();
  void InvokeMenuMethod(const std::string& method);
  void InvokeRecentProject(size_t index);
  void HandleSetRecentProjects(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      menu_channel_;
  HMENU menu_bar_ = nullptr;
  HMENU projects_menu_ = nullptr;
  HMENU recent_projects_menu_ = nullptr;
  HMENU edit_menu_ = nullptr;
  std::vector<RecentProject> recent_projects_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
