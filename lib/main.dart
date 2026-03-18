import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

bool _firebaseReady = false;
bool _googleSignInReady = false;

const _dummyFriendsUri = 'https://example.com/friends';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _firebaseReady = await _initializeFirebase();
  _googleSignInReady = await _initializeGoogleSignIn();
  runApp(const PlanarityApp());
}

Future<bool> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    return true;
  } catch (error, stackTrace) {
    debugPrint('Firebase initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    return false;
  }
}

Future<bool> _initializeGoogleSignIn() async {
  if (kIsWeb) {
    return true;
  }

  try {
    await GoogleSignIn.instance.initialize();
    return true;
  } catch (error, stackTrace) {
    debugPrint('Google Sign-In initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    return false;
  }
}

class PlanarityApp extends StatelessWidget {
  const PlanarityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'planarity',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const PlanarityHomePage(),
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  const black = Colors.black;
  const white = Colors.white;
  final base = ColorScheme.fromSeed(
    seedColor: isDark ? white : black,
    brightness: brightness,
  );

  return ThemeData(
    brightness: brightness,
    colorScheme: base.copyWith(
      primary: isDark ? white : black,
      onPrimary: isDark ? black : white,
      secondary: isDark ? white : black,
      onSecondary: isDark ? black : white,
      error: isDark ? white : black,
      onError: isDark ? black : white,
      surface: isDark ? black : white,
      onSurface: isDark ? white : black,
    ),
    scaffoldBackgroundColor: isDark ? black : white,
    fontFamily: 'GeistMono',
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
      bodyColor: isDark ? white : black,
      displayColor: isDark ? white : black,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? black : white,
      foregroundColor: isDark ? white : black,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: isDark ? white : black,
        foregroundColor: isDark ? black : white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(0),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: isDark ? white : black,
        side: BorderSide(color: isDark ? white : black),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(0),
        ),
      ),
    ),
    dividerColor: isDark ? Colors.white24 : Colors.black26,
    useMaterial3: true,
  );
}

class PlanarityHomePage extends StatefulWidget {
  const PlanarityHomePage({super.key});

  @override
  State<PlanarityHomePage> createState() => _PlanarityHomePageState();
}

enum DailyPlayStatus { ready, inProgress, locked }

class _PlanarityHomePageState extends State<PlanarityHomePage> {
  static final Uri _portfolioUri = Uri.parse(
    'https://wxlfe.dev/?utm_source=planarity.xyz&utm_medium=Self%2BPromotion&utm_campaign=Footer%2BPortfolio%2BLink&utm_id=Footer%2BPortfolio%2BLink&utm_content=Footer%2BPortfolio%2BLink',
  );
  static final Uri _originalGameUri = Uri.parse('http://johntantalo.com/');
  static final Uri _planarGraphInfoUri = Uri.parse('https://en.wikipedia.org/wiki/Planar_graph');
  static const _startingLevel = 4;
  static const _statusKey = 'daily_status';
  static const _levelKey = 'daily_level';
  static const _scoreKey = 'daily_score';
  static const _dayKey = 'daily_day';

  bool _isLoaded = false;
  DailyPlayStatus _status = DailyPlayStatus.ready;
  int _currentLevel = _startingLevel;
  int _score = 0;
  String? _lockedDay;
  StreamSubscription<User?>? _authSubscription;
  String? _activeUserId;
  User? _currentUser;
  Timer? _dailyResetTimer;

  @override
  void initState() {
    super.initState();
    _scheduleDailyReset();
    _loadProgress();
    if (_firebaseReady) {
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen(_handleAuthStateChange);
      _handleAuthStateChange(FirebaseAuth.instance.currentUser);
    }
  }

  @override
  void dispose() {
    _dailyResetTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  String _todayKey() {
    // Use UTC day so every player gets the same graph set for the same date.
    final now = DateTime.now().toUtc();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  void _scheduleDailyReset() {
    _dailyResetTimer?.cancel();
    final now = DateTime.now().toUtc();
    final nextMidnightUtc = DateTime.utc(now.year, now.month, now.day + 1);
    _dailyResetTimer = Timer(nextMidnightUtc.difference(now), () async {
      await _resetForNewDay();
      if (mounted) {
        _scheduleDailyReset();
      }
    });
  }

  Future<void> _resetForNewDay() async {
    final user = _currentUser;
    if (!mounted) {
      return;
    }

    setState(() {
      _status = DailyPlayStatus.ready;
      _currentLevel = _startingLevel;
      _score = 0;
      _lockedDay = null;
    });
    await _saveProgress();

    if (user != null) {
      await _updateUserProgressFields(
        userId: user.uid,
        score: 0,
        currentLevel: _startingLevel,
        locked: false,
      );
    }
  }

  Future<void> _loadProgress() async {
    final prefs = await _prefsOrNull();
    if (prefs == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoaded = true;
      });
      return;
    }

    final today = _todayKey();
    final savedDay = prefs.getString(_dayKey);
    final savedStatusName = prefs.getString(_statusKey);
    DailyPlayStatus? savedStatus;
    for (final status in DailyPlayStatus.values) {
      if (status.name == savedStatusName) {
        savedStatus = status;
        break;
      }
    }
    final savedLevel = prefs.getInt(_levelKey) ?? _startingLevel;
    final savedScore = prefs.getInt(_scoreKey) ?? 0;

    if (!mounted) {
      return;
    }

    setState(() {
      if (savedDay == today && savedStatus != null) {
        _lockedDay = savedDay;
        _status = savedStatus;
        _currentLevel = max(_startingLevel, savedLevel);
        _score = max(0, savedScore);
      } else {
        _lockedDay = null;
        _status = DailyPlayStatus.ready;
        _currentLevel = _startingLevel;
        _score = 0;
      }
      _isLoaded = true;
    });

    if (savedDay != today) {
      await prefs
        ..remove(_statusKey)
        ..remove(_levelKey)
        ..remove(_scoreKey)
        ..remove(_dayKey);
    }
  }

  Future<void> _handleAuthStateChange(User? user) async {
    final nextUserId = user?.uid;
    if (nextUserId == _activeUserId) {
      return;
    }
    _activeUserId = nextUserId;

    if (user == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _currentUser = null;
        _status = DailyPlayStatus.ready;
        _currentLevel = _startingLevel;
        _score = 0;
        _lockedDay = null;
      });
      await _saveProgress();
      return;
    }

    final profileData = await _loadUserDocument(user.uid);
    final lastPlayed = _profileLastPlayed(profileData);
    final playedToday = lastPlayed == _todayKey();
    final syncedScore = _profileScore(profileData, playedToday: playedToday);
    final syncedLevel = _profileCurrentLevel(profileData, playedToday: playedToday);
    final isLocked = _profileLocked(profileData);
    final today = _todayKey();

    if (!mounted) {
      return;
    }

    setState(() {
      _currentUser = user;
      _status = playedToday
          ? (isLocked ? DailyPlayStatus.locked : DailyPlayStatus.inProgress)
          : DailyPlayStatus.ready;
      _currentLevel = syncedLevel;
      _score = syncedScore;
      _lockedDay = playedToday ? today : null;
    });
    await _saveProgress();

    if (!playedToday && (isLocked || syncedScore != 0 || syncedLevel != _startingLevel)) {
      await _updateUserProgressFields(
        userId: user.uid,
        score: 0,
        currentLevel: _startingLevel,
        locked: false,
      );
    }
  }

  Future<void> _saveProgress() async {
    final prefs = await _prefsOrNull();
    if (prefs == null) {
      return;
    }

    if (_lockedDay == null) {
      await prefs
        ..remove(_statusKey)
        ..remove(_levelKey)
        ..remove(_scoreKey)
        ..remove(_dayKey);
      return;
    }

    await prefs.setString(_statusKey, _status.name);
    await prefs.setInt(_levelKey, _currentLevel);
    await prefs.setInt(_scoreKey, _score);
    await prefs.setString(_dayKey, _lockedDay!);
  }

  Future<void> _syncCurrentScoreToFirestore({int addedScore = 0}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    await _updateUserProgressFields(
      userId: user.uid,
      score: _score,
      lifetimeScoreIncrement: addedScore > 0 ? addedScore : null,
    );
  }

  Future<void> _updateUserProgressFields({
    required String userId,
    int? score,
    int? currentLevel,
    String? lastPlayed,
    bool? locked,
    int? lifetimeScoreIncrement,
  }) async {
    final data = <String, Object>{};
    if (score != null) {
      data['score'] = score;
    }
    if (currentLevel != null) {
      data['currentLevel'] = currentLevel;
    }
    if (lastPlayed != null) {
      data['lastPlayed'] = lastPlayed;
    }
    if (locked != null) {
      data['locked'] = locked;
    }
    if (lifetimeScoreIncrement != null && lifetimeScoreIncrement > 0) {
      data['lifetimeScore'] = FieldValue.increment(lifetimeScoreIncrement);
    }
    if (data.isEmpty) {
      return;
    }

    await FirebaseFirestore.instance.collection('users').doc(userId).set(
          data,
          SetOptions(merge: true),
        );
  }

  Future<SharedPreferences?> _prefsOrNull() async {
    try {
      return await SharedPreferences.getInstance();
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _openChallenge() async {
    if (_status == DailyPlayStatus.locked) {
      setState(() {});
      return;
    }

    final today = _todayKey();
    final startLevel = _currentLevel;
    final startScore = _score;
    setState(() {
      _status = DailyPlayStatus.inProgress;
      _lockedDay = today;
      _currentLevel = startLevel;
      _score = startScore;
    });
    await _saveProgress();
    await _updateSignedInProgressForToday(locked: false);

    final result = await Navigator.of(context).push<GameSessionResult>(
      MaterialPageRoute(
        builder: (_) => PlanarityGamePage(
          dayKey: today,
          startLevel: startLevel,
          startScore: startScore,
        ),
      ),
    );

    if (!mounted || result == null) {
      if (mounted) {
        setState(() {});
      }
      return;
    }

    final previousScore = _score;
    setState(() {
      _score = result.score;
      _lockedDay = result.dayKey;
      if (result.locked) {
        _status = DailyPlayStatus.locked;
        _currentLevel = result.level;
      } else {
        _status = DailyPlayStatus.inProgress;
        _currentLevel = result.level;
      }
    });
    await _saveProgress();
    await _updateSignedInProgressForToday(
      currentLevel: result.level,
      locked: result.locked,
    );
    await _syncCurrentScoreToFirestore(
      addedScore: max(0, result.score - previousScore),
    );
  }

  Future<void> _updateSignedInProgressForToday({
    int? currentLevel,
    required bool locked,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    await _updateUserProgressFields(
      userId: user.uid,
      currentLevel: currentLevel ?? _currentLevel,
      lastPlayed: _todayKey(),
      locked: locked,
    );
  }

  Future<String?> _submitAuth({
    required bool isSignIn,
    required String email,
    required String password,
  }) async {
    final cleanedEmail = email.trim().toLowerCase();
    final cleanedPassword = password.trim();

    if (cleanedEmail.isEmpty || cleanedPassword.isEmpty) {
      return 'enter email and password';
    }
    final emailValid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(cleanedEmail);
    if (!emailValid) {
      return 'enter a valid email';
    }
    if (cleanedPassword.length < 6) {
      return 'password must be at least 6 characters';
    }
    if (!_firebaseReady) {
      return 'auth configuration is missing';
    }

    try {
      if (isSignIn) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: cleanedEmail,
          password: cleanedPassword,
        );
      } else {
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: cleanedEmail,
          password: cleanedPassword,
        );
        final user = credential.user;
        if (user == null) {
          return 'unable to create account right now';
        }

        try {
          await _ensureUserDocument(user);
        } on FirebaseException catch (error) {
          await user.delete().catchError((_) {});
          return _firestoreErrorMessage(error);
        } catch (_) {
          await user.delete().catchError((_) {});
          return 'unable to create account right now';
        }
      }
      return null;
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'Firebase auth failed: code=${error.code}, message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
      return _authErrorMessage(error);
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'Firebase auth config failed: code=${error.code}, message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
      return 'auth configuration is missing';
    } catch (error, stackTrace) {
      debugPrint('Unexpected auth failure: $error');
      debugPrintStack(stackTrace: stackTrace);
      return 'unable to authenticate right now';
    }
  }

  Future<_AuthSubmissionResult> _submitGoogleAuth() async {
    if (!_firebaseReady) {
      return const _AuthSubmissionResult(errorText: 'auth configuration is missing');
    }
    if (!kIsWeb && (!_googleSignInReady || !GoogleSignIn.instance.supportsAuthenticate())) {
      return const _AuthSubmissionResult(
        errorText: 'google sign-in is not available on this platform',
      );
    }

    try {
      final credential = await _signInWithGoogle();
      final user = credential.user;
      if (user == null) {
        return const _AuthSubmissionResult(errorText: 'unable to authenticate right now');
      }

      if (credential.additionalUserInfo?.isNewUser ?? false) {
        await _ensureUserDocument(user);
      }

      return _AuthSubmissionResult(
        userToEdit: credential.additionalUserInfo?.isNewUser ?? false ? user : null,
      );
    } on GoogleSignInException catch (error, stackTrace) {
      debugPrint(
        'Google sign-in failed: code=${error.code.name}, description=${error.description}',
      );
      debugPrintStack(stackTrace: stackTrace);
      return _AuthSubmissionResult(errorText: _googleAuthErrorMessage(error));
    } on PlatformException catch (error, stackTrace) {
      debugPrint(
        'Google platform auth failed: code=${error.code}, message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
      return _AuthSubmissionResult(errorText: _googlePlatformAuthErrorMessage(error));
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'Firebase Google auth failed: code=${error.code}, message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
      return _AuthSubmissionResult(errorText: _authErrorMessage(error));
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'Google auth config failed: code=${error.code}, message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
      return _AuthSubmissionResult(errorText: _firestoreErrorMessage(error));
    } catch (error, stackTrace) {
      debugPrint('Unexpected Google auth failure: $error');
      debugPrintStack(stackTrace: stackTrace);
      return const _AuthSubmissionResult(errorText: 'unable to authenticate right now');
    }
  }

  Future<UserCredential> _signInWithGoogle() async {
    if (kIsWeb) {
      return FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
    }

    final googleUser = await GoogleSignIn.instance.authenticate();
    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(idToken: googleAuth.idToken);
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<void> _ensureUserDocument(User user) async {
    return FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'displayName': _defaultDisplayName(user),
      'currentLevel': _startingLevel,
      'lastPlayed': _todayKey(),
      'locked': false,
      'lifetimeScore': 0,
      'score': 0,
    }, SetOptions(merge: true));
  }

  String _defaultDisplayName(User user) {
    final authDisplayName = user.displayName?.trim();
    if (authDisplayName != null && authDisplayName.isNotEmpty) {
      return authDisplayName;
    }
    return 'anonymous player';
  }

  String _authErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'account exists. sign in instead';
      case 'invalid-email':
        return 'enter a valid email';
      case 'weak-password':
        return 'password is too weak';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'invalid email or password';
      case 'too-many-requests':
        return 'too many attempts. try again later';
      case 'operation-not-allowed':
        return 'email/password sign-in is not enabled';
      case 'app-not-authorized':
      case 'invalid-api-key':
        return 'auth configuration is invalid for this app';
      case 'keychain-error':
        return 'macos keychain access is not configured';
      case 'network-request-failed':
        return 'network error. check your connection';
      default:
        return 'unable to authenticate right now';
    }
  }

  String? _googleAuthErrorMessage(GoogleSignInException error) {
    switch (error.code) {
      case GoogleSignInExceptionCode.canceled:
        return '';
      case GoogleSignInExceptionCode.clientConfigurationError:
        return 'google sign-in is not configured for this app';
      default:
        if (error.description != null && error.description!.isNotEmpty) {
          return error.description;
        }
        return 'unable to authenticate right now';
    }
  }

  String _googlePlatformAuthErrorMessage(PlatformException error) {
    final message = error.message;
    if (message != null && message.contains('missing support for the following URL schemes')) {
      return 'google sign-in is not configured for this iOS app';
    }
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return 'unable to authenticate right now';
  }

  String _firestoreErrorMessage(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'unable to create your profile right now';
      case 'network-request-failed':
      case 'unavailable':
        return 'network error. check your connection';
      default:
        return 'unable to create account right now';
    }
  }

  Future<void> _showAuthModal({required bool isSignIn}) async {
    var nextMode = isSignIn;

    while (mounted) {
      final result = await showDialog<_AuthDialogResult>(
        context: context,
        builder: (dialogContext) {
          return _AuthDialog(
            isSignIn: nextMode,
            onSubmit: _submitAuth,
            onGoogleSubmit: _submitGoogleAuth,
          );
        },
      );

      if (!mounted || result == null) {
        return;
      }

      if (result.nextIsSignIn != null) {
        nextMode = result.nextIsSignIn!;
        continue;
      }

      if (result.userToEdit != null) {
        await _showProfileModal(user: result.userToEdit!);
      }
      return;
    }
  }

  Future<void> _showProfileModal({required User user}) async {
    final profileData = await _loadUserDocument(user.uid);
    if (!mounted) {
      return;
    }
    final initialDisplayName = _profileDisplayName(profileData, user);
    final lifetimeScore = _profileLifetimeScore(profileData);
    final result = await showDialog<_ProfileDialogResult>(
      context: context,
      builder: (dialogContext) {
        return _ProfileDialog(
          initialDisplayName: initialDisplayName,
          lifetimeScore: lifetimeScore,
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

    if (result.signOutRequested) {
      await _saveDisplayName(
        user: user,
        displayName: result.displayName,
      );
      if (!mounted) {
        return;
      }
      if (!kIsWeb && _googleSignInReady && GoogleSignIn.instance.supportsAuthenticate()) {
        await GoogleSignIn.instance.signOut().catchError((_) {});
      }
      await FirebaseAuth.instance.signOut();
      return;
    }

    if (result.shouldPersist) {
      await _saveDisplayName(
        user: user,
        displayName: result.displayName,
      );
    }
  }

  Future<Map<String, dynamic>?> _loadUserDocument(String uid) async {
    final snapshot = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return snapshot.data();
  }

  String _profileDisplayName(Map<String, dynamic>? profileData, User user) {
    final profileDisplayName = profileData?['displayName'];
    if (profileDisplayName is String && profileDisplayName.trim().isNotEmpty) {
      return profileDisplayName.trim();
    }

    final authDisplayName = user.displayName?.trim();
    if (authDisplayName != null && authDisplayName.isNotEmpty) {
      return authDisplayName;
    }

    return 'anonymous player';
  }

  int _profileLifetimeScore(Map<String, dynamic>? profileData) {
    final lifetimeScore = profileData?['lifetimeScore'];
    if (lifetimeScore is int) {
      return lifetimeScore;
    }
    if (lifetimeScore is num) {
      return lifetimeScore.toInt();
    }
    return 0;
  }

  int _profileScore(Map<String, dynamic>? profileData, {required bool playedToday}) {
    if (!playedToday) {
      return 0;
    }
    final score = profileData?['score'];
    if (score is int) {
      return max(0, score);
    }
    if (score is num) {
      return max(0, score.toInt());
    }
    return 0;
  }

  int _profileCurrentLevel(Map<String, dynamic>? profileData, {required bool playedToday}) {
    if (!playedToday) {
      return _startingLevel;
    }
    final currentLevel = profileData?['currentLevel'];
    if (currentLevel is int) {
      return max(_startingLevel, currentLevel);
    }
    if (currentLevel is num) {
      return max(_startingLevel, currentLevel.toInt());
    }
    return _startingLevel;
  }

  String? _profileLastPlayed(Map<String, dynamic>? profileData) {
    final lastPlayed = profileData?['lastPlayed'];
    if (lastPlayed is String && lastPlayed.isNotEmpty) {
      return lastPlayed;
    }
    return null;
  }

  bool _profileLocked(Map<String, dynamic>? profileData) {
    final locked = profileData?['locked'];
    if (locked is bool) {
      return locked;
    }
    return false;
  }

  Future<void> _saveDisplayName({
    required User user,
    required String displayName,
  }) async {
    final cleanedDisplayName = displayName.trim().isEmpty ? 'anonymous player' : displayName.trim();
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'displayName': cleanedDisplayName,
    }, SetOptions(merge: true));
    await user.updateDisplayName(cleanedDisplayName);
    await user.reload();
  }

  Future<void> _showAboutModal() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);

        return Dialog(
          backgroundColor: theme.colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.35)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'about',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'goal',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'solve as many graphs as you can each day with as few moves as possible.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'why every puzzle is solvable',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "every graph in planarity is solvable because it's a planar graph. a planar graph is a graph that can be drawn on a flat surface so that no edges cross, except where they meet at shared vertices.",
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      await launchUrl(
                        _planarGraphInfoUri,
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    child: Text(
                      'wikipedia: planar graph',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildHomeScaffold(context, _currentUser);
  }

  Widget _buildHomeScaffold(BuildContext context, User? user) {
    if (!_isLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isLocked = _status == DailyPlayStatus.locked;
    final isWide = MediaQuery.of(context).size.width >= 900;
    final buttonLabel = switch (_status) {
      DailyPlayStatus.ready => 'start',
      DailyPlayStatus.inProgress => 'continue',
      DailyPlayStatus.locked => 'locked',
    };
    final homeContent = _HomeHeroContent(
      buttonLabel: buttonLabel,
      scoreLabel: '$_score',
      isLocked: isLocked,
      onPlayPressed: _openChallenge,
      showLeaderboardBelowButton: !isWide,
      leaderboard: _LeaderboardCard(user: user),
      onPortfolioTap: () async {
        await launchUrl(_portfolioUri, mode: LaunchMode.externalApplication);
      },
      onOriginalGameTap: () async {
        await launchUrl(_originalGameUri, mode: LaunchMode.externalApplication);
      },
    );

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pageBody = Stack(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: isWide
                        ? Row(
                            children: [
                              Expanded(flex: 11, child: homeContent),
                              const SizedBox(width: 40),
                              Expanded(flex: 9, child: _LeaderboardCard(user: user)),
                            ],
                          )
                        : homeContent,
                  ),
                ),
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    onPressed: _showAboutModal,
                    icon: const FaIcon(FontAwesomeIcons.circleQuestion, size: 22),
                    tooltip: 'about',
                  ),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    onPressed: () {
                      if (user == null) {
                        _showAuthModal(isSignIn: false);
                        return;
                      }
                      _showProfileModal(user: user);
                    },
                    icon: const FaIcon(FontAwesomeIcons.circleUser, size: 22),
                    tooltip: 'account',
                  ),
                ),
              ],
            );

            if (isWide) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: SizedBox.expand(
                  child: pageBody,
                ),
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(child: pageBody),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeHeroContent extends StatelessWidget {
  const _HomeHeroContent({
    required this.buttonLabel,
    required this.scoreLabel,
    required this.isLocked,
    required this.onPlayPressed,
    required this.showLeaderboardBelowButton,
    required this.leaderboard,
    required this.onPortfolioTap,
    required this.onOriginalGameTap,
  });

  final String buttonLabel;
  final String scoreLabel;
  final bool isLocked;
  final VoidCallback onPlayPressed;
  final bool showLeaderboardBelowButton;
  final Widget leaderboard;
  final VoidCallback onPortfolioTap;
  final VoidCallback onOriginalGameTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Spacer(),
        const _AnimatedHomeIcon(),
        const SizedBox(height: 20),
        Text(
          'planarity',
          style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
        ),
        const SizedBox(height: 10),
        Text(
          'untangle the graph',
          style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w400,
              ),
        ),
        const SizedBox(height: 21),
        Text(
          'daily score',
          style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
        ),
        const SizedBox(height: 4),
        Text(
          scoreLabel,
          style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 21),
        OutlinedButton(
          onPressed: isLocked ? null : onPlayPressed,
          style: ButtonStyle(
            side: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.disabled)) {
                return BorderSide(
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
                );
              }
              return BorderSide(color: theme.colorScheme.onSurface);
            }),
            foregroundColor: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.disabled)) {
                return theme.colorScheme.onSurface.withOpacity(0.3);
              }
              return theme.colorScheme.onSurface;
            }),
          ),
          child: Text(
            buttonLabel,
            style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
        if (showLeaderboardBelowButton) ...[
          const SizedBox(height: 28),
          leaderboard,
        ],
        const Spacer(),
        Column(
          children: [
            InkWell(
              onTap: onPortfolioTap,
              child: Text(
                '© nate wolfe',
                style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.55),
                      decoration: TextDecoration.underline,
                    ),
              ),
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: onOriginalGameTap,
              child: Text(
                'original by john tantalo',
                style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.55),
                      decoration: TextDecoration.underline,
                    ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AuthDialogResult {
  const _AuthDialogResult({
    this.nextIsSignIn,
    this.userToEdit,
  });

  final bool? nextIsSignIn;
  final User? userToEdit;
}

class _AuthSubmissionResult {
  const _AuthSubmissionResult({
    this.errorText,
    this.userToEdit,
  });

  final String? errorText;
  final User? userToEdit;
}

class _ProfileDialogResult {
  const _ProfileDialogResult({
    required this.displayName,
    required this.shouldPersist,
    required this.signOutRequested,
  });

  final String displayName;
  final bool shouldPersist;
  final bool signOutRequested;
}

class _AuthDialog extends StatefulWidget {
  const _AuthDialog({
    required this.isSignIn,
    required this.onSubmit,
    required this.onGoogleSubmit,
  });

  final bool isSignIn;
  final Future<String?> Function({
    required bool isSignIn,
    required String email,
    required String password,
  }) onSubmit;
  final Future<_AuthSubmissionResult> Function() onGoogleSubmit;

  @override
  State<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<_AuthDialog> {
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  String? _errorText;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    final submitError = await widget.onSubmit(
      isSignIn: widget.isSignIn,
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (!mounted) {
      return;
    }

    if (submitError == null) {
      Navigator.of(context).pop(
        _AuthDialogResult(
          userToEdit: widget.isSignIn ? null : FirebaseAuth.instance.currentUser,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = false;
      _errorText = submitError;
    });
  }

  Future<void> _submitGoogle() async {
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    final result = await widget.onGoogleSubmit();

    if (!mounted) {
      return;
    }

    if (result.errorText == null) {
      Navigator.of(context).pop(
        _AuthDialogResult(userToEdit: result.userToEdit),
      );
      return;
    }

    setState(() {
      _isSubmitting = false;
      _errorText = result.errorText!.isEmpty ? null : result.errorText;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionLabel = widget.isSignIn ? 'sign in' : 'sign up';
    final subtitle = widget.isSignIn
        ? 'sign in with your email and password.'
        : 'create an account with your email and password.';
    final switchPrompt = widget.isSignIn ? 'new here?' : 'already signed up?';
    final switchAction = widget.isSignIn ? 'sign up' : 'sign in';

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.35)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                actionLabel,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.72),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'email',
                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'password',
                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                ),
                onSubmitted: _isSubmitting ? null : (_) async => _submit(),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.75),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(actionLabel),
                ),
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: theme.colorScheme.onSurface.withOpacity(0.25)),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.center,
                child: IconButton.outlined(
                  onPressed: _isSubmitting ? null : _submitGoogle,
                  tooltip: 'continue with Google',
                  icon: const FaIcon(FontAwesomeIcons.google, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: theme.colorScheme.onSurface.withOpacity(0.25)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    switchPrompt,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () {
                            Navigator.of(context).pop(
                              _AuthDialogResult(nextIsSignIn: !widget.isSignIn),
                            );
                          },
                    child: Text(switchAction),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({
    required this.initialDisplayName,
    required this.lifetimeScore,
  });

  final String initialDisplayName;
  final int lifetimeScore;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final TextEditingController _displayNameController;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(text: widget.initialDisplayName);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.35)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'profile',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'update how your name appears in your profile.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.72),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _displayNameController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'display name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                ),
                onSubmitted: (_) {
                  Navigator.of(context).pop(
                    _ProfileDialogResult(
                      displayName: _displayNameController.text,
                      shouldPersist: true,
                      signOutRequested: false,
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              Text(
                'lifetime score',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.lifetimeScore}',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _ProfileDialogResult(
                        displayName: _displayNameController.text,
                        shouldPersist: false,
                        signOutRequested: true,
                      ),
                    );
                  },
                  child: const Text('sign out'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _LeaderboardTab { friends, global }

class _LeaderboardCard extends StatefulWidget {
  const _LeaderboardCard({this.user});

  final User? user;

  @override
  State<_LeaderboardCard> createState() => _LeaderboardCardState();
}

class _LeaderboardCardState extends State<_LeaderboardCard> {
  late _LeaderboardTab _selectedTab;

  bool get _isSignedIn => widget.user != null;

  bool get _friendsEnabled => _isSignedIn;

  bool get _hasFriends => false;

  @override
  void initState() {
    super.initState();
    _selectedTab = _defaultTab;
  }

  @override
  void didUpdateWidget(covariant _LeaderboardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signedInChanged = (oldWidget.user != null) != _isSignedIn;
    if (signedInChanged || (!_friendsEnabled && _selectedTab == _LeaderboardTab.friends)) {
      setState(() {
        _selectedTab = _defaultTab;
      });
    }
  }

  _LeaderboardTab get _defaultTab =>
      _isSignedIn ? _LeaderboardTab.friends : _LeaderboardTab.global;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.22)),
      ),
      child: const _LeaderboardCardContents(),
    );
  }
}

class _TemporarilyBlurredLeaderboard extends StatelessWidget {
  const _TemporarilyBlurredLeaderboard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      // Temporary presentation treatment for unreleased leaderboard data.
      imageFilter: ui.ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
      child: child,
    );
  }
}

class _LeaderboardCardContents extends StatelessWidget {
  const _LeaderboardCardContents();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_LeaderboardCardState>()!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'coming soon - leaderboard',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const _TemporarilyBlurredLeaderboard(
          child: _LeaderboardBlurredBody(),
        ),
      ],
    );
  }
}

class _LeaderboardBlurredBody extends StatelessWidget {
  const _LeaderboardBlurredBody();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_LeaderboardCardState>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _LeaderboardTabButton(
                label: 'Friends',
                selected: state._selectedTab == _LeaderboardTab.friends,
                enabled: state._friendsEnabled,
                onPressed: null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _LeaderboardTabButton(
                label: 'Global',
                selected: state._selectedTab == _LeaderboardTab.global,
                enabled: true,
                onPressed: null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: state._selectedTab == _LeaderboardTab.friends
              ? _FriendsLeaderboardView(
                  key: const ValueKey('friends'),
                  user: state.widget.user,
                  hasFriends: state._hasFriends,
                )
              : _GlobalLeaderboardView(
                  key: const ValueKey('global'),
                  user: state.widget.user,
                ),
        ),
      ],
    );
  }
}

class _LeaderboardTabButton extends StatelessWidget {
  const _LeaderboardTabButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface;

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? color : Colors.transparent,
        foregroundColor: selected ? theme.colorScheme.surface : color,
        side: BorderSide(
          color: enabled ? color : color.withOpacity(0.24),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: enabled
              ? (selected ? theme.colorScheme.surface : color)
              : color.withOpacity(0.3),
        ),
      ),
    );
  }
}

class _FriendsLeaderboardView extends StatelessWidget {
  const _FriendsLeaderboardView({
    super.key,
    required this.user,
    required this.hasFriends,
  });

  final User? user;
  final bool hasFriends;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signedInUser = user;

    if (signedInUser == null) {
      return Text(
        'sign in to compare your score with friends.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withOpacity(0.72),
        ),
      );
    }

    if (!hasFriends) {
      return Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          Text(
            "you haven't added any friends.",
            style: theme.textTheme.bodyMedium,
          ),
          InkWell(
            onTap: () async {
              await launchUrl(Uri.parse(_dummyFriendsUri));
            },
            child: Text(
              'add some here.',
              style: theme.textTheme.bodyMedium?.copyWith(
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      );
    }

    final entries = _friendsEntriesFor(signedInUser);
    return _LeaderboardTable(
      entries: entries,
      subtitle: 'you and your friends',
    );
  }
}

class _GlobalLeaderboardView extends StatelessWidget {
  const _GlobalLeaderboardView({
    super.key,
    required this.user,
  });

  final User? user;

  @override
  Widget build(BuildContext context) {
    final entries = _globalEntriesFor(user);
    final topEntry = entries.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _LeaderboardMetric(
          label: 'global top score',
          value: '${topEntry.score}',
          detail: topEntry.name,
        ),
        const SizedBox(height: 14),
        _LeaderboardTable(
          entries: entries,
          subtitle: user == null ? 'global snapshot' : 'your global position',
        ),
      ],
    );
  }
}

class _LeaderboardMetric extends StatelessWidget {
  const _LeaderboardMetric({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          detail,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.72),
          ),
        ),
      ],
    );
  }
}

class _LeaderboardTable extends StatelessWidget {
  const _LeaderboardTable({
    required this.entries,
    required this.subtitle,
  });

  final List<_LeaderboardEntry> entries;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 10),
        ...entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    '#${entry.rank}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.75),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    entry.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: entry.isCurrentUser ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${entry.score}',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LeaderboardEntry {
  const _LeaderboardEntry({
    required this.rank,
    required this.name,
    required this.score,
    this.isCurrentUser = false,
  });

  final int rank;
  final String name;
  final int score;
  final bool isCurrentUser;
}

List<_LeaderboardEntry> _friendsEntriesFor(User user) {
  final playerName = _displayNameForUser(user);
  return [
    _LeaderboardEntry(rank: 1, name: 'mia', score: 41),
    _LeaderboardEntry(rank: 2, name: playerName, score: 36, isCurrentUser: true),
    _LeaderboardEntry(rank: 3, name: 'rory', score: 29),
    _LeaderboardEntry(rank: 4, name: 'alex', score: 25),
  ];
}

List<_LeaderboardEntry> _globalEntriesFor(User? user) {
  final entries = <_LeaderboardEntry>[
    const _LeaderboardEntry(rank: 1, name: 'top score', score: 98),
    const _LeaderboardEntry(rank: 2, name: 'sana', score: 94),
    const _LeaderboardEntry(rank: 3, name: 'lee', score: 89),
  ];

  if (user == null) {
    entries.add(const _LeaderboardEntry(rank: 154, name: 'guest', score: 12));
    return entries;
  }

  entries.add(
    _LeaderboardEntry(
      rank: 28,
      name: _displayNameForUser(user),
      score: 47,
      isCurrentUser: true,
    ),
  );
  return entries;
}

String _displayNameForUser(User user) {
  final displayName = user.displayName?.trim();
  if (displayName != null && displayName.isNotEmpty) {
    return displayName.toLowerCase();
  }
  final email = user.email?.trim().toLowerCase();
  if (email != null && email.isNotEmpty) {
    return email.split('@').first;
  }
  return 'you';
}

class PlanarityGamePage extends StatefulWidget {
  const PlanarityGamePage({
    super.key,
    required this.dayKey,
    required this.startLevel,
    required this.startScore,
  });

  final String dayKey;
  final int startLevel;
  final int startScore;

  @override
  State<PlanarityGamePage> createState() => _PlanarityGamePageState();
}

class _PlanarityGamePageState extends State<PlanarityGamePage> {
  late int _level;
  late int _totalScore;
  late PlanarityLevel _current;
  int _movesUsed = 0;
  int? _activeNode;
  Offset? _dragStart;
  bool _resolvingLevel = false;
  Size? _lastBoardSize;
  bool _needsCentering = true;
  bool _recenterScheduled = false;

  @override
  void initState() {
    super.initState();
    _level = widget.startLevel;
    _totalScore = widget.startScore;
    _current = PlanarityGenerator.generate(dayKey: widget.dayKey, level: _level);
  }

  void _startNextLevel() {
    setState(() {
      _level += 1;
      _movesUsed = 0;
      _activeNode = null;
      _dragStart = null;
      _current = PlanarityGenerator.generate(dayKey: widget.dayKey, level: _level);
      _needsCentering = true;
    });
  }

  void _failRun() {
    Navigator.of(context).pop(
      GameSessionResult(
        dayKey: widget.dayKey,
        score: _totalScore,
        level: _level,
        locked: true,
      ),
    );
  }

  void _exitToHome({int? level}) {
    Navigator.of(context).pop(
      GameSessionResult(
        dayKey: widget.dayKey,
        score: _totalScore,
        level: level ?? _level,
        locked: false,
      ),
    );
  }

  bool _isSolved() => _countCrossings(_current.nodes, _current.edges) == 0;

  void _onPanStart(int index, DragStartDetails details) {
    if (_resolvingLevel) {
      return;
    }
    _activeNode = index;
    _dragStart = _current.nodes[index];
  }

  void _onPanUpdate(int index, DragUpdateDetails details, Size boardSize) {
    if (_activeNode != index || _resolvingLevel) {
      return;
    }

    final raw = _current.nodes[index] + details.delta;
    final clamped = Offset(
      raw.dx.clamp(20.0, boardSize.width - 20.0),
      raw.dy.clamp(20.0, boardSize.height - 20.0),
    );

    setState(() {
      _current.nodes[index] = clamped;
    });
  }

  Future<void> _onPanEnd(int index) async {
    if (_activeNode != index || _dragStart == null) {
      _activeNode = null;
      _dragStart = null;
      return;
    }

    final moved = (_current.nodes[index] - _dragStart!).distance > 0.5;
    _activeNode = null;
    _dragStart = null;

    if (!moved) {
      return;
    }

    setState(() {
      _movesUsed += 1;
    });

    if (_isSolved()) {
      if (_resolvingLevel) {
        return;
      }
      _resolvingLevel = true;
      final levelScore = scoreForSolvedLevel(level: _level, movesUsed: _movesUsed);
      setState(() {
        _totalScore += levelScore;
      });
      final solvedNodes = List<Offset>.from(_current.nodes);
      final solvedEdges = List<Edge>.from(_current.edges);
      final proceed = await _showCompletionModal(
        solved: true,
        totalMoves: _level,
        movesUsed: _movesUsed,
        totalScore: _totalScore,
        nodes: solvedNodes,
        edges: solvedEdges,
      );
      _resolvingLevel = false;
      if (!mounted) {
        return;
      }
      if (!proceed) {
        _exitToHome(level: _level + 1);
        return;
      }
      _startNextLevel();
      return;
    }

    if (_movesUsed >= _level) {
      if (_resolvingLevel) {
        return;
      }
      _resolvingLevel = true;
      final finalNodes = List<Offset>.from(_current.nodes);
      final finalEdges = List<Edge>.from(_current.edges);
      await _showCompletionModal(
        solved: false,
        totalMoves: _level,
        movesUsed: _movesUsed,
        totalScore: _totalScore,
        nodes: finalNodes,
        edges: finalEdges,
      );
      _resolvingLevel = false;
      if (!mounted) {
        return;
      }
      _failRun();
    }
  }

  @override
  Widget build(BuildContext context) {
    final crossingEdges = _findIntersectingEdges(_current.nodes, _current.edges);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: _exitToHome,
                        icon: const FaIcon(FontAwesomeIcons.arrowLeft, size: 18),
                        tooltip: 'back',
                      ),
                    ),
                    Text(
                      'planarity',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                          ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '$_totalScore',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'untangle the graph',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
                    ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MoveDots(
                    totalMoves: _level,
                    movesUsed: _movesUsed,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: Theme.of(context).dividerColor),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final boardSize = Size(constraints.maxWidth, constraints.maxHeight);
                    _maybeRecenterForBoard(boardSize);

                    return Stack(
                      children: [
                        CustomPaint(
                          size: boardSize,
                          painter: GraphPainter(
                            nodes: _current.nodes,
                            edges: _current.edges,
                            intersectingEdges: crossingEdges,
                            isDark: Theme.of(context).brightness == Brightness.dark,
                          ),
                        ),
                        ...List.generate(_current.nodes.length, (index) {
                          final position = _current.nodes[index];
                          return Positioned(
                            left: position.dx - 10,
                            top: position.dy - 10,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (details) => _onPanStart(index, details),
                              onPanUpdate: (details) => _onPanUpdate(index, details, boardSize),
                              onPanEnd: (_) {
                                _onPanEnd(index);
                              },
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _maybeRecenterForBoard(Size boardSize) {
    final sizeChanged = _lastBoardSize == null ||
        (_lastBoardSize!.width - boardSize.width).abs() > 0.5 ||
        (_lastBoardSize!.height - boardSize.height).abs() > 0.5;
    if (!_needsCentering && !sizeChanged) {
      return;
    }
    if (_recenterScheduled) {
      return;
    }
    _recenterScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _recenterScheduled = false;
        return;
      }
      setState(() {
        _centerNodesInBoard(boardSize);
        _lastBoardSize = boardSize;
        _needsCentering = false;
        _recenterScheduled = false;
      });
    });
  }

  void _centerNodesInBoard(Size boardSize) {
    if (_current.nodes.isEmpty) {
      return;
    }

    const padding = 20.0;
    double minX = _current.nodes.first.dx;
    double maxX = _current.nodes.first.dx;
    double minY = _current.nodes.first.dy;
    double maxY = _current.nodes.first.dy;
    for (final node in _current.nodes) {
      minX = min(minX, node.dx);
      maxX = max(maxX, node.dx);
      minY = min(minY, node.dy);
      maxY = max(maxY, node.dy);
    }

    final currentCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final targetCenter = Offset(boardSize.width / 2, boardSize.height / 2);
    var dx = targetCenter.dx - currentCenter.dx;
    var dy = targetCenter.dy - currentCenter.dy;

    final minDx = padding - minX;
    final maxDx = (boardSize.width - padding) - maxX;
    final minDy = padding - minY;
    final maxDy = (boardSize.height - padding) - maxY;
    dx = dx.clamp(minDx, maxDx);
    dy = dy.clamp(minDy, maxDy);

    for (var i = 0; i < _current.nodes.length; i++) {
      final shifted = _current.nodes[i] + Offset(dx, dy);
      _current.nodes[i] = Offset(
        shifted.dx.clamp(padding, boardSize.width - padding),
        shifted.dy.clamp(padding, boardSize.height - padding),
      );
    }
  }

  Future<bool> _showCompletionModal({
    required bool solved,
    required int totalMoves,
    required int movesUsed,
    required int totalScore,
    required List<Offset> nodes,
    required List<Edge> edges,
  }) async {
    final continuePlay = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          solved ? 'solved ${nodes.length} nodes' : 'failed ${nodes.length} nodes',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          await _shareSolvedCard(
                            solved: solved,
                            totalMoves: totalMoves,
                            movesUsed: movesUsed,
                            totalScore: totalScore,
                            nodes: nodes,
                            edges: edges,
                            isDark: Theme.of(context).brightness == Brightness.dark,
                          );
                        },
                        icon: const FaIcon(FontAwesomeIcons.shareNodes, size: 18),
                        tooltip: 'share',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: _MoveDots(
                      totalMoves: totalMoves,
                      movesUsed: movesUsed,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 180,
                    width: double.infinity,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final fittedNodes = _normalizeNodesToRect(
                          nodes,
                          (Offset.zero & Size(constraints.maxWidth, 180)).deflate(14),
                        );
                        final fittedCrossings = _findIntersectingEdges(fittedNodes, edges);
                        return CustomPaint(
                          painter: GraphPainter(
                            nodes: fittedNodes,
                            edges: edges,
                            intersectingEdges: fittedCrossings,
                            isDark: Theme.of(context).brightness == Brightness.dark,
                            drawNodes: true,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('home'),
                      ),
                      if (solved)
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Text('continue - $totalScore'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return continuePlay ?? false;
  }

  Future<void> _shareSolvedCard({
    required bool solved,
    required int totalMoves,
    required int movesUsed,
    required int totalScore,
    required List<Offset> nodes,
    required List<Edge> edges,
    required bool isDark,
  }) async {
    try {
      final bytes = await _buildShareImage(
        solved: solved,
        totalMoves: totalMoves,
        movesUsed: movesUsed,
        totalScore: totalScore,
        nodes: nodes,
        edges: edges,
        isDark: isDark,
      );
      final file = XFile.fromData(
        bytes,
        mimeType: 'image/png',
        name: solved ? 'planarity-solved.png' : 'planarity-failed.png',
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [file],
          text: solved ? 'planarity — graph solved' : 'planarity — run ended',
        ),
      );
    } on MissingPluginException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Share is unavailable on this build.')),
      );
    }
  }

  Future<Uint8List> _buildShareImage({
    required bool solved,
    required int totalMoves,
    required int movesUsed,
    required int totalScore,
    required List<Offset> nodes,
    required List<Edge> edges,
    required bool isDark,
  }) async {
    const width = 1080.0;
    const height = 1350.0;
    const graphTop = 330.0;
    const graphSide = 120.0;
    const graphHeight = 880.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));
    final bgColor = isDark ? Colors.black : Colors.white;
    final fgColor = isDark ? Colors.white : Colors.black;

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, width, height),
      Paint()..color = bgColor,
    );

    final title = TextPainter(
      text: TextSpan(
        text: 'planarity',
        style: TextStyle(color: fgColor, fontSize: 62, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const iconSize = 72.0;
    const iconGap = 16.0;
    final headingWidth = iconSize + iconGap + title.width;
    final headingStartX = (width - headingWidth) / 2;
    final iconRect = Rect.fromLTWH(headingStartX, 62, iconSize, iconSize);
    _drawShareBrandIcon(canvas, iconRect);
    title.paint(
      canvas,
      Offset(
        headingStartX + iconSize + iconGap,
        iconRect.top + (iconSize - title.height) / 2,
      ),
    );

    final subtitle = TextPainter(
      text: TextSpan(
        text: 'untangle the graph',
        style: TextStyle(color: fgColor.withOpacity(0.75), fontSize: 34, fontWeight: FontWeight.w400),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    subtitle.paint(canvas, Offset((width - subtitle.width) / 2, 150));

    final dotFill = Paint()..color = fgColor;
    final dotStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = fgColor;
    const dotRadius = 10.0;
    const dotGap = 11.0;
    final rowWidth = (totalMoves * dotRadius * 2) + ((totalMoves - 1) * dotGap);
    var x = (width - rowWidth) / 2 + dotRadius;
    const y = 248.0;
    final solidCount = max(0, totalMoves - movesUsed);
    for (var i = 0; i < totalMoves; i++) {
      final center = Offset(x, y);
      if (i < solidCount) {
        canvas.drawCircle(center, dotRadius, dotFill);
      }
      canvas.drawCircle(center, dotRadius, dotStroke);
      x += (dotRadius * 2) + dotGap;
    }

    final graphRect = Rect.fromLTWH(graphSide, graphTop, width - (2 * graphSide), graphHeight);
    canvas.drawRect(
      graphRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = fgColor.withOpacity(0.28),
    );

    if (nodes.isNotEmpty) {
      final normalized = _normalizeNodesToRect(nodes, graphRect.deflate(24));
      final crossingEdges = _findIntersectingEdges(normalized, edges);
      final edgePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = fgColor.withOpacity(0.88);
      final crossingEdgePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = fgColor.withOpacity(0.28);
      for (final edge in edges) {
        if (crossingEdges.contains(edge)) {
          _drawDottedLine(canvas, normalized[edge.a], normalized[edge.b], crossingEdgePaint, 16, 10);
        } else {
          canvas.drawLine(normalized[edge.a], normalized[edge.b], edgePaint);
        }
      }
      final nodePaint = Paint()..color = fgColor;
      for (final node in normalized) {
        canvas.drawCircle(node, 12, nodePaint);
      }
    }

    final image = await recorder.endRecording().toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  List<Offset> _normalizeNodesToRect(List<Offset> nodes, Rect target) {
    final xs = nodes.map((p) => p.dx).toList()..sort();
    final ys = nodes.map((p) => p.dy).toList()..sort();
    final minX = xs.first;
    final maxX = xs.last;
    final minY = ys.first;
    final maxY = ys.last;
    final spanX = max(maxX - minX, 1.0);
    final spanY = max(maxY - minY, 1.0);
    final scale = min(target.width / spanX, target.height / spanY);
    final usedW = spanX * scale;
    final usedH = spanY * scale;
    final offsetX = target.left + (target.width - usedW) / 2;
    final offsetY = target.top + (target.height - usedH) / 2;

    return nodes.map((node) {
      return Offset(
        offsetX + ((node.dx - minX) * scale),
        offsetY + ((node.dy - minY) * scale),
      );
    }).toList(growable: false);
  }
}

class GraphPainter extends CustomPainter {
  GraphPainter({
    required this.nodes,
    required this.edges,
    required this.intersectingEdges,
    required this.isDark,
    this.drawNodes = false,
  });

  final List<Offset> nodes;
  final List<Edge> edges;
  final Set<Edge> intersectingEdges;
  final bool isDark;
  final bool drawNodes;

  @override
  void paint(Canvas canvas, Size size) {
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = isDark ? Colors.white70 : Colors.black87;
    final intersectingEdgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = isDark ? Colors.white24 : Colors.black26;

    for (final edge in edges) {
      final p1 = nodes[edge.a];
      final p2 = nodes[edge.b];
      if (intersectingEdges.contains(edge)) {
        _drawDottedLine(canvas, p1, p2, intersectingEdgePaint, 8, 6);
      } else {
        canvas.drawLine(p1, p2, edgePaint);
      }
    }

    if (drawNodes) {
      final nodePaint = Paint()..color = isDark ? Colors.white : Colors.black;
      for (final node in nodes) {
        canvas.drawCircle(node, 5.2, nodePaint);
      }
    }

  }

  @override
  bool shouldRepaint(covariant GraphPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.edges != edges ||
        oldDelegate.intersectingEdges != intersectingEdges ||
        oldDelegate.isDark != isDark ||
        oldDelegate.drawNodes != drawNodes;
  }
}

class _MoveDots extends StatelessWidget {
  const _MoveDots({
    required this.totalMoves,
    required this.movesUsed,
    required this.color,
  });

  final int totalMoves;
  final int movesUsed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final solidCount = max(0, totalMoves - movesUsed);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(totalMoves, (index) {
          final isHollow = index >= solidCount;
          return Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isHollow ? Colors.transparent : color,
              border: Border.all(color: color, width: 1.2),
            ),
          );
        }),
      ),
    );
  }
}

class _AnimatedHomeIcon extends StatefulWidget {
  const _AnimatedHomeIcon();

  @override
  State<_AnimatedHomeIcon> createState() => _AnimatedHomeIconState();
}

class _AnimatedHomeIconState extends State<_AnimatedHomeIcon> with TickerProviderStateMixin {
  static const _edges = <Edge>[
    Edge(0, 1),
    Edge(1, 2),
    Edge(2, 3),
    Edge(3, 4),
    Edge(4, 0),
    Edge(0, 2),
    Edge(1, 3),
  ];

  final Random _random = Random();
  late final AnimationController _driftController;
  late final AnimationController _scrambleController;
  late List<Offset> _baseNodes;
  late List<Offset> _scrambleFromNodes;
  late List<Offset> _scrambleToNodes;
  late List<double> _phaseX;
  late List<double> _phaseY;

  @override
  void initState() {
    super.initState();
    _baseNodes = _initialNodes();
    _scrambleFromNodes = _baseNodes;
    _scrambleToNodes = _baseNodes;
    _phaseX = List<double>.generate(_baseNodes.length, (_) => _random.nextDouble() * 2 * pi);
    _phaseY = List<double>.generate(_baseNodes.length, (_) => _random.nextDouble() * 2 * pi);
    _driftController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    _scrambleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _baseNodes = _scrambleToNodes;
          });
          _scrambleController.reset();
        }
      });
  }

  @override
  void dispose() {
    _driftController.dispose();
    _scrambleController.dispose();
    super.dispose();
  }

  List<Offset> _initialNodes() {
    // Coordinates normalized from public/icon-source.svg (viewBox 0..1024).
    return const <Offset>[
      Offset(0.50, 0.189),
      Offset(0.797, 0.404),
      Offset(0.684, 0.754),
      Offset(0.316, 0.754),
      Offset(0.203, 0.404),
    ];
  }

  void _scramble() {
    final currentAnchor = _currentAnchorNodes();
    final target = _scrambledNodes();
    setState(() {
      _scrambleFromNodes = currentAnchor;
      _scrambleToNodes = target;
      _phaseX = List<double>.generate(_baseNodes.length, (_) => _random.nextDouble() * 2 * pi);
      _phaseY = List<double>.generate(_baseNodes.length, (_) => _random.nextDouble() * 2 * pi);
    });
    _scrambleController
      ..reset()
      ..forward();
  }

  List<Offset> _scrambledNodes() {
    const minDistance = 0.18;
    const minBound = 0.18;
    const maxBound = 0.82;
    final nodes = <Offset>[];

    var attempts = 0;
    while (nodes.length < 5 && attempts < 500) {
      attempts += 1;
      final candidate = Offset(
        minBound + _random.nextDouble() * (maxBound - minBound),
        minBound + _random.nextDouble() * (maxBound - minBound),
      );
      final tooClose = nodes.any((node) => (node - candidate).distance < minDistance);
      if (!tooClose) {
        nodes.add(candidate);
      }
    }

    if (nodes.length == 5) {
      return nodes;
    }
    return _initialNodes();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final edgeColor = isDark ? const Color(0xFFF4F4F5).withOpacity(0.26) : Colors.black.withOpacity(0.28);
    final nodeColor = isDark ? const Color(0xFFF4F4F5).withOpacity(0.94) : Colors.black.withOpacity(0.92);
    final glowColor = isDark ? const Color(0xFFF4F4F5).withOpacity(0.08) : Colors.black.withOpacity(0.08);

    return GestureDetector(
      onTap: _scramble,
      child: SizedBox(
        width: 138,
        height: 138,
        child: AnimatedBuilder(
          animation: Listenable.merge([_driftController, _scrambleController]),
          builder: (context, _) {
            final t = _driftController.value * 2 * pi;
            final anchorNodes = _currentAnchorNodes();
            final animatedNodes = List<Offset>.generate(anchorNodes.length, (index) {
              final base = anchorNodes[index];
              final dx = sin(t + _phaseX[index]) * 0.012;
              final dy = cos(t + _phaseY[index]) * 0.012;
              return Offset(
                (base.dx + dx).clamp(0.12, 0.88),
                (base.dy + dy).clamp(0.12, 0.88),
              );
            });

            return CustomPaint(
              painter: _HomeIconPainter(
                nodes: animatedNodes,
                edges: _edges,
                edgeColor: edgeColor,
                nodeColor: nodeColor,
                glowColor: glowColor,
              ),
            );
          },
        ),
      ),
    );
  }

  List<Offset> _currentAnchorNodes() {
    if (!_scrambleController.isAnimating) {
      return _baseNodes;
    }

    final curved = Curves.easeInOutCubic.transform(_scrambleController.value);
    return List<Offset>.generate(_scrambleFromNodes.length, (index) {
      return Offset.lerp(_scrambleFromNodes[index], _scrambleToNodes[index], curved)!;
    });
  }
}

class _HomeIconPainter extends CustomPainter {
  const _HomeIconPainter({
    required this.nodes,
    required this.edges,
    required this.edgeColor,
    required this.nodeColor,
    required this.glowColor,
  });

  final List<Offset> nodes;
  final List<Edge> edges;
  final Color edgeColor;
  final Color nodeColor;
  final Color glowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final pxNodes = nodes
        .map((n) => Offset(
              n.dx * size.width,
              n.dy * size.height,
            ))
        .toList(growable: false);

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = edgeColor;
    for (final edge in edges) {
      canvas.drawLine(pxNodes[edge.a], pxNodes[edge.b], edgePaint);
    }

    final glowPaint = Paint()..color = glowColor;
    for (final p in pxNodes) {
      canvas.drawCircle(p, 12, glowPaint);
    }

    final nodePaint = Paint()..color = nodeColor;
    for (final p in pxNodes) {
      canvas.drawCircle(p, 6.8, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HomeIconPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.edges != edges ||
        oldDelegate.edgeColor != edgeColor ||
        oldDelegate.nodeColor != nodeColor ||
        oldDelegate.glowColor != glowColor;
  }
}

class PlanarityLevel {
  PlanarityLevel({required this.nodes, required this.edges});

  final List<Offset> nodes;
  final List<Edge> edges;
}

class PlanarityGenerator {
  static PlanarityLevel generate({required String dayKey, required int level}) {
    final nodeCount = max(2, level);
    final structureRandom = Random(_stableSeed(dayKey, level));
    final embedding = _circleLayout(nodeCount);
    final edges = _buildPlanarEdges(embedding, structureRandom);
    final positionsRandom = Random(_stableSeed(dayKey, 0));
    final scattered = _scatterNodes(nodeCount, positionsRandom);

    if (nodeCount >= 4 && edges.isNotEmpty) {
      var attempts = 0;
      while (_countCrossings(scattered, edges) == 0 && attempts < 30) {
        for (var i = 0; i < scattered.length; i++) {
          scattered[i] = _randomPoint(positionsRandom);
        }
        attempts += 1;
      }
    }

    return PlanarityLevel(nodes: scattered, edges: edges);
  }

  static List<Offset> _circleLayout(int n) {
    if (n == 1) {
      return const [Offset(0, 0)];
    }

    return List.generate(n, (i) {
      final angle = (2 * pi * i) / n;
      return Offset(cos(angle), sin(angle));
    });
  }

  static List<Offset> _scatterNodes(int n, Random random) {
    return List.generate(n, (_) => _randomPoint(random));
  }

  static Offset _randomPoint(Random random) {
    return Offset(
      50 + random.nextDouble() * 260,
      60 + random.nextDouble() * 420,
    );
  }

  static List<Edge> _buildPlanarEdges(List<Offset> embedding, Random random) {
    final n = embedding.length;
    if (n <= 1) {
      return const <Edge>[];
    }

    final edges = <Edge>{};

    for (var i = 0; i < n; i++) {
      edges.add(Edge(i, (i + 1) % n));
    }

    final candidates = <Edge>[];
    for (var a = 0; a < n; a++) {
      for (var b = a + 1; b < n; b++) {
        final isCycleNeighbor = (b == a + 1) || (a == 0 && b == n - 1);
        if (!isCycleNeighbor) {
          candidates.add(Edge(a, b));
        }
      }
    }

    candidates.shuffle(random);
    for (final candidate in candidates) {
      final crossesExisting = edges.any((existing) {
        if (existing.sharesNode(candidate)) {
          return false;
        }
        return _segmentsIntersect(
          embedding[candidate.a],
          embedding[candidate.b],
          embedding[existing.a],
          embedding[existing.b],
        );
      });
      if (!crossesExisting && random.nextDouble() < 0.55) {
        edges.add(candidate);
      }
    }

    return edges.toList(growable: false);
  }

  // Stable seed hash (FNV-1a style) to keep generation consistent across runs/platforms.
  static int _stableSeed(String dayKey, int level) {
    final input = '$dayKey|$level';
    var hash = 0x811C9DC5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}

class Edge {
  const Edge(int x, int y)
      : a = x < y ? x : y,
        b = x < y ? y : x;

  final int a;
  final int b;

  bool sharesNode(Edge other) {
    return a == other.a || a == other.b || b == other.a || b == other.b;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Edge && other.a == a && other.b == b;
  }

  @override
  int get hashCode => Object.hash(a, b);
}

class GameSessionResult {
  GameSessionResult({
    required this.dayKey,
    required this.score,
    required this.level,
    required this.locked,
  });

  final String dayKey;
  final int score;
  final int level;
  final bool locked;
}

int scoreForSolvedLevel({required int level, required int movesUsed}) {
  return max(0, level - movesUsed);
}

int _countCrossings(List<Offset> nodes, List<Edge> edges) {
  return _findIntersectingEdges(nodes, edges).length;
}

Set<Edge> _findIntersectingEdges(List<Offset> nodes, List<Edge> edges) {
  final intersecting = <Edge>{};
  for (var i = 0; i < edges.length; i++) {
    for (var j = i + 1; j < edges.length; j++) {
      final e1 = edges[i];
      final e2 = edges[j];
      if (e1.sharesNode(e2)) {
        continue;
      }

      if (_segmentsIntersect(nodes[e1.a], nodes[e1.b], nodes[e2.a], nodes[e2.b])) {
        intersecting
          ..add(e1)
          ..add(e2);
      }
    }
  }
  return intersecting;
}

bool _segmentsIntersect(Offset p1, Offset p2, Offset q1, Offset q2) {
  final o1 = _orientation(p1, p2, q1);
  final o2 = _orientation(p1, p2, q2);
  final o3 = _orientation(q1, q2, p1);
  final o4 = _orientation(q1, q2, p2);

  return o1 * o2 < 0 && o3 * o4 < 0;
}

double _orientation(Offset a, Offset b, Offset c) {
  return (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
}

void _drawDottedLine(
  Canvas canvas,
  Offset start,
  Offset end,
  Paint paint,
  double dashLength,
  double dashGap,
) {
  final total = (end - start).distance;
  if (total == 0) {
    return;
  }
  final direction = (end - start) / total;
  var distance = 0.0;
  while (distance < total) {
    final dashEnd = min(distance + dashLength, total);
    final p1 = start + (direction * distance);
    final p2 = start + (direction * dashEnd);
    canvas.drawLine(p1, p2, paint);
    distance += dashLength + dashGap;
  }
}

void _drawShareBrandIcon(Canvas canvas, Rect rect) {
  final bgPaint = Paint()..color = const Color(0xFF0F1319);
  final edgePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = rect.width * 0.018
    ..color = const Color(0xFFF4F4F5).withOpacity(0.26);
  final glowPaint = Paint()..color = const Color(0xFFF4F4F5).withOpacity(0.08);
  final nodePaint = Paint()..color = const Color(0xFFF4F4F5).withOpacity(0.94);

  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.215)),
    bgPaint,
  );

  final nodes = <Offset>[
    Offset(rect.left + rect.width * 0.500, rect.top + rect.height * 0.189),
    Offset(rect.left + rect.width * 0.797, rect.top + rect.height * 0.404),
    Offset(rect.left + rect.width * 0.684, rect.top + rect.height * 0.754),
    Offset(rect.left + rect.width * 0.316, rect.top + rect.height * 0.754),
    Offset(rect.left + rect.width * 0.203, rect.top + rect.height * 0.404),
  ];
  const edges = <Edge>[
    Edge(0, 1),
    Edge(1, 2),
    Edge(2, 3),
    Edge(3, 4),
    Edge(4, 0),
    Edge(0, 2),
    Edge(1, 3),
  ];

  for (final edge in edges) {
    canvas.drawLine(nodes[edge.a], nodes[edge.b], edgePaint);
  }
  for (final node in nodes) {
    canvas.drawCircle(node, rect.width * 0.084, glowPaint);
  }
  for (final node in nodes) {
    canvas.drawCircle(node, rect.width * 0.051, nodePaint);
  }
}
