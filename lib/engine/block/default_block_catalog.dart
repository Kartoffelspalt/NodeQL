import 'package:nodeql/domain/models/block_models.dart';

const defaultBlockCatalog = <BlockMetadata>[
  BlockMetadata(
    type: 'motion.move_steps',
    translationKey: 'blockMoveSteps',
    arguments: <String>['steps'],
  ),
  BlockMetadata(
    type: 'control.repeat',
    translationKey: 'blockRepeatTimes',
    arguments: <String>['times'],
    isContainer: true,
  ),
  BlockMetadata(
    type: 'events.when_flag_clicked',
    translationKey: 'blockWhenFlagClicked',
  ),
];
