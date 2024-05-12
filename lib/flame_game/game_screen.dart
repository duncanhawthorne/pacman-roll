import '../audio/audio_controller.dart';
import 'endless_runner.dart';
import 'constants.dart';

import '../level_selection/levels.dart';
import '../player_progress/player_progress.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nes_ui/nes_ui.dart';
import 'package:provider/provider.dart';

import 'game_lose_dialog.dart';
import 'game_won_dialog.dart';
import 'package:elapsed_time_display/elapsed_time_display.dart';

/// This widget defines the properties of the game screen.
///
/// It mostly sets up the overlays (widgets shown on top of the Flame game) and
/// the gets the [AudioController] from the context and passes it in to the
/// [EndlessRunner] class so that it can play audio.
class GameScreen extends StatelessWidget {
  const GameScreen({required this.level, super.key});

  final GameLevel level;

  static const String loseDialogKey = 'lose_dialog';
  static const String wonDialogKey = 'won_dialog';
  static const String backButtonKey = 'back_buttton';
  static const String statusOverlay = 'status_overlay';

  @override
  Widget build(BuildContext context) {
    final audioController = context.read<AudioController>();
    return Scaffold(
      body: GameWidget<EndlessRunner>(
        key: const Key('play session'),
        game: EndlessRunner(
          level: level,
          playerProgress: context.read<PlayerProgress>(),
          audioController: audioController,
        ),
        overlayBuilderMap: {
          backButtonKey: (BuildContext context, EndlessRunner game) {
            return Positioned(
              top: 20,
              left: 30,
              child: NesButton(
                type: NesButtonType.normal,
                onPressed: () =>
                    {GoRouter.of(context).go("/"), gameRunning = false},
                child: NesIcon(
                    iconData: NesIcons.leftArrowIndicator,
                    size: const Size(15, 15)),
              ),
            );
          },
          statusOverlay: (BuildContext context, EndlessRunner game) {
            return Positioned(
              top: 20,
              right: 30,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ValueListenableBuilder<int>(
                    builder: (BuildContext context, int value, Widget? child) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8.0),
                        child: Text(
                            "Lives: ${3 - game.world.numberOfDeaths.value}",
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white)),
                      );
                    },
                    valueListenable: game.world.numberOfDeaths,
                  ),
                  ElapsedTimeDisplay(
                    startTime: DateTime.fromMillisecondsSinceEpoch(
                        game.world.datetimeStarted.millisecondsSinceEpoch),
                    interval: const Duration(milliseconds: 100),
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    formatter: (elapsedTime) {
                      String secondsStr =
                          (elapsedTime.minutes * 60 + elapsedTime.seconds)
                              .toString();
                      String hundredthSecondsStr =
                          (elapsedTime.milliseconds / 100)
                              .truncate()
                              .toString();

                      return 'Time: $secondsStr.$hundredthSecondsStr';
                    },
                  ),
                ],
              ),
            );
          },
          loseDialogKey: (BuildContext context, EndlessRunner game) {
            return GameLoseDialog(
              level: level,
              levelCompletedIn:
                  (game.world.getCurrentOrCompleteLevelTimeSeconds()).toInt(),
            );
          },
          wonDialogKey: (BuildContext context, EndlessRunner game) {
            return GameWonDialog(
              level: level,
              levelCompletedIn:
                  game.world.getCurrentOrCompleteLevelTimeSeconds(),
            );
          },
        },
      ),
    );
  }
}
