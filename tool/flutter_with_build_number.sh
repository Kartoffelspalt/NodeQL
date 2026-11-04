# Source this file from a NodeQL checkout to increment the local build number
# immediately before every `flutter run` invocation.
#
# Usage: source tool/flutter_with_build_number.sh
flutter() {
  local argument repository_root

  for argument in "$@"; do
    case "$argument" in
      run)
        repository_root="$(git rev-parse --show-toplevel 2>/dev/null)" || break
        if [[ -f "$repository_root/tool/increment_build_number.dart" ]]; then
          dart "$repository_root/tool/increment_build_number.dart" \
            --pubspec "$repository_root/pubspec.yaml" || return $?
        fi
        break
        ;;
      analyze|attach|build|channel|clean|config|create|devices|doctor|drive|emulators|format|gen-l10n|install|logs|precache|pub|screenshot|symbolize|test|upgrade)
        break
        ;;
    esac
  done

  command flutter "$@"
}
