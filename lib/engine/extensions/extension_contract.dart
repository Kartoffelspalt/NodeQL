import 'package:scratchql_creater/domain/models/block_models.dart';

abstract class ScratchQlExtension {
  String get id;
  String get name;

  List<BlockMetadata> get blocks;
}
