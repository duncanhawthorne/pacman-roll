import 'dart:math';

import 'package:flame_forge2d/flame_forge2d.dart';

import '../level_selection/levels.dart';
import '../player_progress/player_progress.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flame/src/events/messages/pointer_move_event.dart'
    as dhpointer_move_event;

import '../../audio/sounds.dart';
import 'game_screen.dart';
import 'components/player.dart';
import 'components/compass.dart';
import 'components/maze.dart';
import 'constants.dart';
import 'helper.dart';

import 'package:sensors_plus/sensors_plus.dart';

import 'package:flutter/foundation.dart';

import '../audio/audio_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:audioplayers/audioplayers.dart';


/// The world is where you place all the components that should live inside of
/// the game, like the player, enemies, obstacles and points for example.
/// The world can be much bigger than what the camera is currently looking at,
/// but in this game all components that go outside of the size of the viewport
/// are removed, since the player can't interact with those anymore.
///
/// The [EndlessWorld] has two mixins added to it:
///  - The [TapCallbacks] that makes it possible to react to taps (or mouse
///  clicks) on the world.
///  - The [HasGameReference] that gives the world access to a variable called
///  `game`, which is a reference to the game class that the world is attached
///  to.
class EndlessWorld extends Forge2DWorld
    with TapCallbacks, HasGameReference, DragCallbacks, PointerMoveCallbacks {
  EndlessWorld({
    required this.level,
    required this.playerProgress,
    Random? random,
  }) : _random = random ?? Random();

  /// The properties of the current level.
  final GameLevel level;



  /// Used to see what the current progress of the player is and to update the
  /// progress if a level is finished.
  final PlayerProgress playerProgress;

  /// In the [scoreNotifier] we keep track of what the current score is, and if
  /// other parts of the code is interested in when the score is updated they
  /// can listen to it and act on the updated value.
  final scoreNotifier = ValueNotifier(0);
  late RealCharacter player;
  late final DateTime timeStarted;
  Vector2 get size => (parent as FlameGame).size;

  int levelCompletedIn = 0;
  late final AudioController audioController;
  get getAudioController => audioController;
  int pelletsRemaining = 1;
  Vector2 dragLastPosition = Vector2(0,0);
  Vector2 targetFromLastDrag = Vector2(-50,0); //makes smooth start for drag

  /// The random number generator that is used to spawn periodic components.
  // ignore: unused_field
  final Random _random;

  /// The gravity is defined in virtual pixels per second squared.
  /// These pixels are in relation to how big the [FixedResolutionViewport] is.
  //@override
  //final Vector2 gravity = Vector2(0, 100);
  //Vector2 get worldGravity => gravity; //_worldGravity;
  //Vector2 _worldGravity = Vector2(0, 0); //initial value which immediately gets overridden
  double worldAngle = 0; //2 * pi / 8;

  /// Where the ground is located in the world and things should stop falling.
  //late final double groundLevel = (size.y / 2) - (size.y / 5);

  List<RealCharacter> ghostPlayersList = [];

  void play(SfxType type) async {
    // ignore: dead_code
    if (false) {
      audioController.playSfx(type);
    }
    else {
      final dAudioPlayer = AudioPlayer();
      if (type == SfxType.ghostsScared) {
        dAudioPlayer.setReleaseMode(ReleaseMode.loop);
        Future.delayed(const Duration(milliseconds: kGhostChaseTimeMillis), () {
          dAudioPlayer.stop();
        });
      }
      if (type == SfxType.siren) {
        dAudioPlayer.setReleaseMode(ReleaseMode.loop);
        updateSirenVolume(dAudioPlayer);
      }
      String filename = soundTypeToFilename(type)[0];
      await dAudioPlayer.setSource(AssetSource('sfx/$filename'));
      await dAudioPlayer.resume();
    }
  }

 double getTargetSirenVolume() {
    double tmpSirenVolume = 0;
    try {
      for (int i = 0; i < 3; i++) {
        tmpSirenVolume +=
        ghostPlayersList[i].current == CharacterState.normal
            ? ghostPlayersList[i]
            .getUnderlyingBallVelocity()
            .length
            : 0;
      }
      if (player.current == CharacterState.deadPacman || !globalPhysicsLinked) {
        tmpSirenVolume = 0;
      }
    }
    // ignore: empty_catches
    catch(e) {

    }
    return min(0.4, tmpSirenVolume / 100);
  }

  void updateSirenVolume(dAudioPlayer) {
    dAudioPlayer.setVolume(getTargetSirenVolume());
    Future.delayed(const Duration(milliseconds: 100), () {
      updateSirenVolume(dAudioPlayer);
    });
  }

  void addGhost(world, int number) {
    RealCharacter ghost = RealCharacter(
        isGhost: true,
        startingPosition: kGhostStartLocation +
            Vector2(getSingleSquareWidth() * (number - 1), 0));
    ghost.ghostNumber = number;
    world.add(ghost);
    ghostPlayersList.add(ghost);
  }

  void siren() {
    return;
    /*
    if (sirenVolume != 0) {
      play(SfxType.siren);
    }
    Future.delayed(const Duration(milliseconds: 400), () {
      siren();
    });
     */
  }
  
  @override
  Future<void> onLoad() async {
    if (sirenOn) {
      play(SfxType.siren);
    }
    pelletsRemaining = getStartingNumberPelletsAndSuperPellets(mazeLayout);

    WakelockPlus.toggle(enable: true);

    // Used to keep track of when the level started, so that we later can
    // calculate how long time it took to finish the level.
    timeStarted = DateTime.now();

    if (useGyro) {
      accelerometerEventStream().listen(
        //start once and then runs
        (AccelerometerEvent event) {
            setGravity(Vector2(event.y, event.x - 5) * (android && web ? 25 : 1));
        },
        onError: (error) {
          // Logic to handle error
          // Needed for Android in case sensor is not available
        },
        cancelOnError: true,
      );
    }

    player = RealCharacter(isGhost: false, startingPosition: kPacmanStartLocation);
    add(player);

    for (int i = 0; i < 3; i++) {
      addGhost(this, i);
    }

    addPillsAndPowerPills(this);

    add(Compass());

    // When the player takes a new point we check if the score is enough to
    // pass the level and if it is we calculate what time the level was passed
    // in, update the player's progress and open up a dialog that shows that
    // the player passed the level.
    scoreNotifier.addListener(() {
      if (scoreNotifier.value >= level.winScore) {
        final levelTime = (DateTime.now().millisecondsSinceEpoch -
                timeStarted.millisecondsSinceEpoch) /
            1000;

        levelCompletedIn = levelTime.round();

        playerProgress.setLevelFinished(level.number, levelCompletedIn);
        game.pauseEngine();
        game.overlays.add(GameScreen.winDialogKey);
      }
    });
  }

  @override
  void onMount() {
    super.onMount();
    // When the world is mounted in the game we add a back button widget as an
    // overlay so that the player can go back to the previous screen.
    game.overlays.add(GameScreen.backButtonKey);
  }

  @override
  void onRemove() {
    game.overlays.remove(GameScreen.backButtonKey);
  }

  /// Gives the player points, with a default value +1 points.
  void addScore({int amount = 1}) {
    scoreNotifier.value += amount;
  }

  /// Sets the player's score to 0 again.
  void resetScore() {
    scoreNotifier.value -= 3;
  }

  @override
  void onPointerMove(dhpointer_move_event.PointerMoveEvent event) {
    if (followCursor) {
      handlePointerEvent(Vector2(event.localPosition.x, event.localPosition.y));
    }
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (clickAndDrag) {
      if (iOS) {
        dragLastPosition = Vector2(0,0);
      }
      else {
        dragLastPosition =
            Vector2(event.localPosition.x, event.localPosition.y);
      }
    }
    else if (followCursor) {
      handlePointerEvent(Vector2(event.localPosition.x, event.localPosition.y));
    }
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    if (clickAndDrag) {
      if (dragLastPosition != Vector2(0,0)) {
        Vector2 dragDelta = -(event.localStartPosition - dragLastPosition);
        handlePointerEvent(targetFromLastDrag + dragDelta);
        targetFromLastDrag = targetFromLastDrag + dragDelta;
      }
      dragLastPosition = Vector2(event.localStartPosition.x, event.localStartPosition.y);
    }
    else if (followCursor) {
      handlePointerEvent(Vector2(event.localStartPosition.x, event.localStartPosition.y));
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (clickAndDrag) {
      dragLastPosition = Vector2(0, 0);
    }
  }

  void handlePointerEvent(Vector2 eventVector) {
    if (globalPhysicsLinked && gravityTurnedOn) {
      double impliedAngle = (-eventVector.x / (ksizex/2) * 2* pi) * 20;
      setGravity(screenRotates ? Vector2(cos(impliedAngle), sin(impliedAngle))  : eventVector - player.underlyingBallReal.position);
    }
  }



  void setGravity(Vector2 targetGravity) {
    if (globalPhysicsLinked && gravityTurnedOn) {
      gravity = targetGravity;
      if (normaliseGravity) {
        gravity = gravity.normalized() * 50;
      }
      if (screenRotates) {
        worldAngle = atan2(gravity.x, gravity.y);
      }
    }
  }
}
