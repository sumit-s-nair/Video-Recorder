# Video Recorder with additional sensor data

A Flutter app that records videos with synchronized gyroscope and GPS data. Its good for analyzing camera movement and location while recording (Basically created for my other project to allow it to make better path recommendations) check it out at [Terrain-Aware Path Recommendation](https://github.com/sumit-s-nair/Terrain-Aware-Path-Recommendation)

## What does it do?

This app lets you record videos just like any other camera app, but it also captures:
- **Gyroscope data** - tracks how your phone is rotating and moving
- **GPS coordinates** - records your exact location during filming
- **Real-time display** - see sensor data live while recording

All this data gets saved alongside your video so you can analyze it later for whatever you guys need it for

## Features(well as the title says)

- Real-time GPS tracking with coordinates overlay
- Gyroscope data capture (X, Y, Z rotation)
- Video preview with synchronized sensor data
- Exports data as JSON files for analysis

## How to use(i really dont need to explain how you should take a video now should i but here you go)

1. **Grant permissions** - The app needs camera, microphone, and location access
2. **Start recording** - Tap the big record button(idt you can miss it)
3. **Stuff gets recorded** - See your gyroscope and GPS data update in real-time
4. **Stop when done** - Tap the stop button(please do or it wont stop)
5. **Preview or share** - Use the preview button to watch with sensor overlay, or open in files

## well what gets saved?

For each video recording, you get:
- `video_TIMESTAMP.mp4` - Your actual video file
- `video_TIMESTAMP_sensors.json` - All the sensor data with timestamps

The JSON file contains:
- Video info (duration, timestamps)
- Frame-by-frame gyroscope readings
- GPS coordinates for each moment
- Metadata about the recording

## Setup (or you can ignore all this and go straight for the build)

1. Clone this repo
2. Run `flutter pub get` to install dependencies
3. Make sure you have camera and location permissions set up
4. Run `flutter run` and start recording

## Dependencies(if your too lazy to read the pubspec.yaml)

- `camera` - For video recording
- `sensors_plus` - Gyroscope data
- `geolocator` - GPS tracking  
- `video_player` - Video preview
- `open_filex` - File management
- `path_provider` - File storage

---

If you made down here it means a lot :)
Have a nice day bbg
