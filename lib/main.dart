// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final cameras = await availableCameras();
    runApp(MyApp(cameras: cameras));
  } catch (e) {
    runApp(const MyApp(cameras: []));
  }
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sensor Video Recorder',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: VideoRecorderScreen(cameras: cameras),
      debugShowCheckedModeBanner: false,
    );
  }
}

class VideoRecorderScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const VideoRecorderScreen({super.key, required this.cameras});

  @override
  State<VideoRecorderScreen> createState() => _VideoRecorderScreenState();
}

class _VideoRecorderScreenState extends State<VideoRecorderScreen> {
  CameraController? _cameraController;
  bool _isRecording = false;
  bool _isInitialized = false;
  Timer? _sensorTimer;
  Timer? _uiUpdateTimer;
  String? _lastRecordedVideoPath;

  // Sensor data
  List<Map<String, dynamic>> _sensorData = [];
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<Position>? _locationSubscription;

  // Current sensor values
  GyroscopeEvent? _currentGyroscope;
  Position? _currentLocation;
  String _recordingDuration = "00:00";
  DateTime? _recordingStartTime;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _requestPermissions();
    _startRealtimeSensorTracking();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full screen camera preview
          if (_cameraController != null &&
              _cameraController!.value.isInitialized)
            Positioned.fill(child: CameraPreview(_cameraController!))
          else
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Initializing Camera...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),

          // Recording border effect
          if (_isRecording)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red, width: 3),
                ),
              ),
            ),

          // Overlay UI
          _buildOverlayInfo(),
        ],
      ),
    );
  }

  Future<void> _requestPermissions() async {
    final Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.locationWhenInUse,
      Permission.storage,
    ].request();

    // Check if all permissions are granted
    for (var status in statuses.values) {
      if (status != PermissionStatus.granted) {
        _showPermissionDialog();
        break;
      }
    }
  }

  void _showPermissionDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning, color: Colors.orange, size: 48),
        title: const Text('Permissions Required'),
        content: const Text(
          'This app needs camera, microphone, and location permissions to function properly. Please grant these permissions in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      if (mounted) {
        _showErrorDialog('No cameras available on this device.');
      }
      return;
    }

    _cameraController = CameraController(
      widget.cameras.first,
      ResolutionPreset.high,
      enableAudio: true,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog(
            'Failed to initialize camera. Please check permissions and try again.');
      }
    }
  }

  void _startRealtimeSensorTracking() {
    // Start gyroscope tracking
    _gyroscopeSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
      if (mounted) {
        setState(() {
          _currentGyroscope = event;
        });
      }
    });

    // Start location tracking
    _startLocationTracking();
  }

  void _startSensorDataCollection() {
    // Collect sensor data every 33ms (30 FPS) during recording
    _sensorTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (!_isRecording) {
        timer.cancel();
        return;
      }

      _sensorData.add({
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'frame_number': _sensorData.length + 1,
        'gyroscope': _currentGyroscope != null
            ? {
                'x': _currentGyroscope!.x,
                'y': _currentGyroscope!.y,
                'z': _currentGyroscope!.z,
              }
            : null,
        'location': _currentLocation != null
            ? {
                'latitude': _currentLocation!.latitude,
                'longitude': _currentLocation!.longitude,
                'altitude': _currentLocation!.altitude,
                'accuracy': _currentLocation!.accuracy,
                'heading': _currentLocation!.heading,
                'speed': _currentLocation!.speed,
              }
            : null,
      });
    });

    // Update recording duration
    _uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isRecording || _recordingStartTime == null) {
        timer.cancel();
        return;
      }

      final duration = DateTime.now().difference(_recordingStartTime!);
      if (mounted) {
        setState(() {
          _recordingDuration =
              "${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}";
        });
      }
    });
  }

  void _startLocationTracking() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );

      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          if (mounted) {
            setState(() {
              _currentLocation = position;
            });
          }
        },
        onError: (error) {
          // Location tracking failed, but continue without it
        },
      );
    } catch (e) {
      // Location services unavailable, continue without location data
    }
  }

  void _stopSensorTracking() {
    _sensorTimer?.cancel();
    _uiUpdateTimer?.cancel();
  }

  Future<String> _getVideoPath() async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    return '${appDir.path}/video_$timestamp.mp4';
  }

  Future<void> _startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _showErrorDialog('Camera not ready. Please wait for initialization.');
      return;
    }

    try {
      await _cameraController!.startVideoRecording();

      _sensorData.clear();
      _recordingStartTime = DateTime.now();
      _startSensorDataCollection();

      setState(() {
        _isRecording = true;
        _recordingDuration = "00:00";
      });
    } catch (e) {
      _showErrorDialog('Failed to start recording. Please try again.');
    }
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.error, color: Colors.red, size: 48),
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _stopRecording() async {
    if (_cameraController == null || !_isRecording) return;

    try {
      final XFile videoFile = await _cameraController!.stopVideoRecording();
      _stopSensorTracking();

      // Copy video to documents directory
      final String newVideoPath = await _getVideoPath();
      final File originalFile = File(videoFile.path);
      final File newVideoFile = await originalFile.copy(newVideoPath);

      setState(() {
        _isRecording = false;
      });

      // Save sensor data
      await _saveSensorData(newVideoFile.path);
      _showSuccessDialog(newVideoFile.path);
    } catch (e) {
      setState(() {
        _isRecording = false;
      });
      _showErrorDialog('Failed to save recording. Please try again.');
    }
  }

  Future<void> _saveSensorData(String videoPath) async {
    try {
      final String sensorDataPath =
          videoPath.replaceAll('.mp4', '_sensors.json');
      final File sensorFile = File(sensorDataPath);

      final Map<String, dynamic> data = {
        'video_info': {
          'video_path': videoPath,
          'recording_start': _recordingStartTime?.millisecondsSinceEpoch,
          'recording_end': DateTime.now().millisecondsSinceEpoch,
          'duration_seconds': _sensorData.isNotEmpty
              ? (_sensorData.last['timestamp'] -
                      _sensorData.first['timestamp']) /
                  1000
              : 0,
        },
        'metadata': {
          'total_frames': _sensorData.length,
          'fps': 30,
          'sensor_sample_rate': '33ms',
          'app_version': '1.0.0',
        },
        'sensor_data': _sensorData,
      };

      await sensorFile.writeAsString(jsonEncode(data));
    } catch (e) {
      // Sensor data save failed, but video is still saved
    }
  }

  void _showSuccessDialog(String videoPath) {
    if (!mounted) return;
    _lastRecordedVideoPath = videoPath;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: const Text('Recording Saved Successfully'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.videocam, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(child: Text(videoPath.split('/').last)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.analytics, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text('${_sensorData.length} sensor frames captured'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.timer, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text('Duration: $_recordingDuration'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _openInFileManager(videoPath);
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_open, size: 16),
                SizedBox(width: 4),
                Text('Open in Files'),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _openVideoPreview(videoPath);
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow, size: 16),
                SizedBox(width: 4),
                Text('Preview'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openInFileManager(String filePath) async {
    try {
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done) {
        final directory = Directory(filePath).parent.path;
        await OpenFilex.open(directory);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open file manager'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Widget _buildOverlayInfo() {
    return Positioned.fill(
      child: SafeArea(
        child: Column(
          children: [
            // Top overlay - App title and recording status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: const Text(
                      'Sensor Recorder',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  if (_isRecording)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.red, Colors.red.shade700],
                        ),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _recordingDuration,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const Spacer(),

            // Bottom overlay - Sensor data and controls
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Sensor data cards
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildSensorCard(
                        'GYRO',
                        Icons.rotate_right,
                        Colors.blue,
                        _currentGyroscope != null
                            ? 'X:${_currentGyroscope!.x.toStringAsFixed(2)}\n'
                                'Y:${_currentGyroscope!.y.toStringAsFixed(2)}\n'
                                'Z:${_currentGyroscope!.z.toStringAsFixed(2)}'
                            : 'No data',
                      ),
                      _buildSensorCard(
                        'GPS',
                        Icons.location_on,
                        Colors.green,
                        _currentLocation != null
                            ? '${_currentLocation!.latitude.toStringAsFixed(5)}\n'
                                '${_currentLocation!.longitude.toStringAsFixed(5)}\n'
                                '${_currentLocation!.altitude.toStringAsFixed(0)}m'
                            : 'No data',
                      ),
                      if (_isRecording)
                        _buildSensorCard(
                          'STATS',
                          Icons.analytics,
                          Colors.red,
                          'Frames: ${_sensorData.length}\n'
                              'Duration: $_recordingDuration',
                        ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  // Control buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton(
                        icon: Icons.play_arrow,
                        isVisible: _lastRecordedVideoPath != null,
                        onTap: () => _openVideoPreview(_lastRecordedVideoPath!),
                        tooltip: 'Preview Last Video',
                      ),
                      _buildRecordButton(),
                      _buildControlButton(
                        icon: Icons.folder_open,
                        isVisible: _lastRecordedVideoPath != null,
                        onTap: () =>
                            _openInFileManager(_lastRecordedVideoPath!),
                        tooltip: 'Open in Files',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorCard(
      String title, IconData icon, Color color, String data) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            data,
            style: TextStyle(
              color: data == 'No data' ? Colors.white54 : Colors.white,
              fontSize: 10,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required bool isVisible,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return isVisible
        ? Tooltip(
            message: tooltip,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.7),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.3), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
            ),
          )
        : const SizedBox(width: 60);
  }

  Widget _buildRecordButton() {
    return GestureDetector(
      onTap: _isRecording ? _stopRecording : _startRecording,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: _isRecording
                ? [Colors.red, Colors.red.shade700]
                : [Colors.white, Colors.grey.shade200],
          ),
          boxShadow: [
            BoxShadow(
              color:
                  (_isRecording ? Colors.red : Colors.white).withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Icon(
          _isRecording ? Icons.stop : Icons.videocam,
          size: 40,
          color: _isRecording ? Colors.white : Colors.black,
        ),
      ),
    );
  }

  void _openVideoPreview(String videoPath) async {
    final String sensorDataPath = videoPath.replaceAll('.mp4', '_sensors.json');
    if (!await File(sensorDataPath).exists()) {
      _showErrorDialog('Sensor data file not found for this video.');
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPreviewScreen(
          videoPath: videoPath,
          sensorDataPath: sensorDataPath,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _gyroscopeSubscription?.cancel();
    _locationSubscription?.cancel();
    _sensorTimer?.cancel();
    _uiUpdateTimer?.cancel();
    super.dispose();
  }
}

// Video Preview Screen
class VideoPreviewScreen extends StatefulWidget {
  final String videoPath;
  final String sensorDataPath;

  const VideoPreviewScreen({
    super.key,
    required this.videoPath,
    required this.sensorDataPath,
  });

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  VideoPlayerController? _videoController;
  bool _isInitialized = false;
  bool _showSensorOverlay = true;
  Map<String, dynamic>? _sensorData;
  Map<String, dynamic>? _currentFrameData;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    _loadSensorData();
  }

  Future<void> _initializeVideo() async {
    _videoController = VideoPlayerController.file(File(widget.videoPath));
    try {
      await _videoController!.initialize();
      setState(() {
        _isInitialized = true;
      });
      _startSensorSync();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load video'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadSensorData() async {
    try {
      final file = File(widget.sensorDataPath);
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        _sensorData = jsonDecode(jsonString);
      }
    } catch (e) {
      // Sensor data loading failed, continue without overlay
    }
  }

  void _startSensorSync() {
    _syncTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_videoController != null &&
          _videoController!.value.isInitialized &&
          _sensorData != null) {
        _updateCurrentFrameData();
      }
    });
  }

  void _updateCurrentFrameData() {
    final currentPosition = _videoController!.value.position.inMilliseconds;
    final videoInfo = _sensorData!['video_info'];
    final recordingStart = videoInfo['recording_start'];

    if (recordingStart != null) {
      final targetTimestamp = recordingStart + currentPosition;
      final sensorDataList = _sensorData!['sensor_data'] as List;

      // Find closest sensor data frame
      Map<String, dynamic>? closestFrame;
      int minDiff = double.maxFinite.toInt();

      for (var frame in sensorDataList) {
        final frameDiff = (frame['timestamp'] - targetTimestamp).abs();
        if (frameDiff < minDiff) {
          minDiff = frameDiff;
          closestFrame = frame;
        }
      }

      if (closestFrame != _currentFrameData) {
        setState(() {
          _currentFrameData = closestFrame;
        });
      }
    }
  }

  Widget _buildSensorOverlay() {
    if (!_showSensorOverlay || _currentFrameData == null) {
      return const SizedBox();
    }

    final gyro = _currentFrameData!['gyroscope'];
    final location = _currentFrameData!['location'];

    return Positioned(
      top: 80,
      left: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Frame: ${_currentFrameData!['frame_number'] ?? 'N/A'}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            if (gyro != null || location != null) const SizedBox(height: 12),
            if (gyro != null) ...[
              Row(
                children: [
                  Icon(Icons.rotate_right, color: Colors.blue, size: 16),
                  const SizedBox(width: 6),
                  const Text(
                    'Gyroscope',
                    style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'X: ${gyro['x']?.toStringAsFixed(3)}\n'
                'Y: ${gyro['y']?.toStringAsFixed(3)}\n'
                'Z: ${gyro['z']?.toStringAsFixed(3)}',
                style: const TextStyle(
                    color: Colors.white, fontSize: 11, height: 1.3),
              ),
              const SizedBox(height: 8),
            ],
            if (location != null) ...[
              Row(
                children: [
                  Icon(Icons.location_on, color: Colors.green, size: 16),
                  const SizedBox(width: 6),
                  const Text(
                    'Location',
                    style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Lat: ${location['latitude']?.toStringAsFixed(6)}\n'
                'Lng: ${location['longitude']?.toStringAsFixed(6)}\n'
                'Alt: ${location['altitude']?.toStringAsFixed(1)}m',
                style: const TextStyle(
                    color: Colors.white, fontSize: 11, height: 1.3),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _videoController == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('Video Preview',
              style: TextStyle(color: Colors.white)),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Loading video...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title:
            const Text('Video Preview', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            onPressed: () => _openInFileManager(widget.videoPath),
            icon: const Icon(Icons.folder_open, color: Colors.white),
            tooltip: 'Open in Files',
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _showSensorOverlay = !_showSensorOverlay;
              });
            },
            icon: Icon(
              _showSensorOverlay ? Icons.visibility : Icons.visibility_off,
              color: Colors.white,
            ),
            tooltip: 'Toggle Sensor Data',
          ),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
          ),
          _buildSensorOverlay(),
          Positioned(
            bottom: 60,
            left: 20,
            right: 20,
            child: Column(
              children: [
                VideoProgressIndicator(
                  _videoController!,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: Colors.red,
                    bufferedColor: Colors.grey.shade600,
                    backgroundColor: Colors.white.withOpacity(0.3),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: IconButton(
                    onPressed: () {
                      setState(() {
                        _videoController!.value.isPlaying
                            ? _videoController!.pause()
                            : _videoController!.play();
                      });
                    },
                    icon: Icon(
                      _videoController!.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openInFileManager(String filePath) async {
    try {
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done) {
        final directory = Directory(filePath).parent.path;
        await OpenFilex.open(directory);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open file manager'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }
}
