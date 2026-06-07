import 'package:nodeql/domain/models/block_models.dart';

abstract class NodeQlExtension {
  String get id;
  String get name;

  List<BlockMetadata> get blocks;
}
